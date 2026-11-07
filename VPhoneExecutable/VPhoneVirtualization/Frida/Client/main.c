// Native, single-session Frida client. stdin/stdout are private JSON-lines pipes
// owned by vphone-vm; credentials never appear in argv or emitted events.
#include "frida-core.h"
#include <stdio.h>
#include <signal.h>
#include <unistd.h>

static GMainLoop *loop;
static FridaDeviceManager *manager;
static FridaDevice *device;
static FridaSession *session;
static FridaScript *script;
static guint spawned_pid;
static gboolean stopping;
static GCancellable *operation;

typedef struct {
  GMutex mutex;
  GCond condition;
  gboolean finished;
  gint64 deadline;
  GCancellable *cancellable;
  GThread *thread;
} VPhoneOperation;

static gpointer watch_operation(gpointer data) {
  VPhoneOperation *timer = data;
  g_mutex_lock(&timer->mutex);
  while (!timer->finished) {
    if (!g_cond_wait_until(&timer->condition, &timer->mutex, timer->deadline)) {
      g_cancellable_cancel(timer->cancellable);
      break;
    }
  }
  g_mutex_unlock(&timer->mutex);
  return NULL;
}

// Independent of both the app and Frida event loops, which may be blocked
// inside a synchronous call or may not have started a backend yet.
static VPhoneOperation *begin_operation(guint seconds) {
  VPhoneOperation *timer = g_new0(VPhoneOperation, 1);
  g_mutex_init(&timer->mutex);
  g_cond_init(&timer->condition);
  timer->cancellable = operation = g_cancellable_new();
  timer->deadline = g_get_monotonic_time() + seconds * G_TIME_SPAN_SECOND;
  timer->thread = g_thread_new("vphone-frida-timeout", watch_operation, timer);
  return timer;
}

static void end_operation(VPhoneOperation *timer) {
  g_mutex_lock(&timer->mutex);
  timer->finished = TRUE;
  g_cond_signal(&timer->condition);
  g_mutex_unlock(&timer->mutex);
  g_thread_join(timer->thread);
  g_cond_clear(&timer->condition);
  g_mutex_clear(&timer->mutex);
  g_clear_object(&operation);
  g_free(timer);
}

static void emit(const gchar *event, const gchar *message, guint pid) {
  JsonObject *object = json_object_new();
  json_object_set_string_member(object, "event", event);
  if (message) json_object_set_string_member(object, "message", message);
  if (pid) json_object_set_int_member(object, "pid", pid);
  JsonNode *node = json_node_new(JSON_NODE_OBJECT);
  json_node_take_object(node, object);
  gchar *line = json_to_string(node, FALSE);
  flockfile(stdout);
  fprintf(stdout, "%s\n", line);
  fflush(stdout);
  funlockfile(stdout);
  g_free(line);
  json_node_free(node);
}

static const gchar *text(JsonObject *object, const gchar *key) {
  JsonNode *node = json_object_get_member(object, key);
  return node && JSON_NODE_HOLDS_VALUE(node) && json_node_get_value_type(node) == G_TYPE_STRING
      ? json_node_get_string(node) : NULL;
}

static gboolean quit(gpointer unused) {
  g_main_loop_quit(loop);
  return G_SOURCE_REMOVE;
}

static void detached(FridaSession *s, FridaSessionDetachReason reason, FridaCrash *crash, gpointer unused) {
  if (!stopping) {
    gchar *description = g_enum_to_string(FRIDA_TYPE_SESSION_DETACH_REASON, reason);
    emit("detached", description, 0);
    g_free(description);
    g_idle_add(quit, NULL);
  }
}

static void message(FridaScript *s, const gchar *json, GBytes *data, gpointer unused) {
  emit("message", json, 0);
  if (data) {
    gchar *encoded = g_base64_encode(g_bytes_get_data(data, NULL), g_bytes_get_size(data));
    emit("data", encoded, 0);
    g_free(encoded);
  }
}

static gboolean load(const gchar *source, GError **error) {
  FridaScriptOptions *options = frida_script_options_new();
  frida_script_options_set_name(options, "vphone-session");
  frida_script_options_set_runtime(options, FRIDA_SCRIPT_RUNTIME_QJS);
  // Compile before removing the previous script, so a syntax error leaves it
  // intact. Runtime load errors are reported and the candidate is discarded.
  FridaScript *candidate = frida_session_create_script_sync(session, source, options, operation, error);
  g_object_unref(options);
  if (!candidate) return FALSE;
  g_signal_connect(candidate, "message", G_CALLBACK(message), NULL);
  if (script) {
    frida_script_unload_sync(script, operation, error);
    if (*error) { g_object_unref(candidate); return FALSE; }
    g_clear_object(&script);
  }
  frida_script_load_sync(candidate, operation, error);
  if (*error) { g_object_unref(candidate); return FALSE; }
  script = candidate;
  return TRUE;
}

static gboolean start(JsonObject *command, GError **error) {
  const gchar *endpoint = text(command, "endpoint");
  const gchar *token = text(command, "token");
  const gchar *mode = text(command, "mode");
  const gchar *target = text(command, "target");
  const gchar *source = text(command, "source");
  if (!endpoint || !*endpoint || !token || !*token || !mode || !target || !*target || !source ||
      (strcmp(mode, "spawn") && strcmp(mode, "attach") && strcmp(mode, "gadget") && strcmp(mode, "probe"))) {
    g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_INVALID_ARGUMENT, "Invalid session request");
    return FALSE;
  }
  FridaRemoteDeviceOptions *options = frida_remote_device_options_new();
  frida_remote_device_options_set_token(options, token);
  device = frida_device_manager_add_remote_device_sync(manager, endpoint, options, operation, error);
  g_object_unref(options);
  if (!device) return FALSE;
  guint pid;
  if (!strcmp(mode, "spawn")) {
    pid = frida_device_spawn_sync(device, target, NULL, operation, error);
    if (*error) return FALSE;
    spawned_pid = pid;
  } else if (!strcmp(mode, "gadget") || !strcmp(mode, "probe")) {
    // A Listen Gadget exposes exactly its own process as "Gadget". Never
    // choose an arbitrary process from a server endpoint supplied by mistake.
    FridaProcessList *processes = frida_device_enumerate_processes_sync(device, NULL, operation, error);
    if (!processes) return FALSE;
    pid = 0;
    if (frida_process_list_size(processes) == 1) {
      FridaProcess *process = frida_process_list_get(processes, 0);
      if (!strcmp(frida_process_get_name(process), "Gadget")) pid = frida_process_get_pid(process);
      g_object_unref(process);
    }
    g_object_unref(processes);
    if (!pid) {
      g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_INVALID_ARGUMENT, "Endpoint is not a single Listen Gadget process");
      return FALSE;
    }
    if (!strcmp(mode, "probe")) {
      emit("connected", "Authenticated Gadget endpoint; no attach or script execution", pid);
      return TRUE;
    }
  } else {
    gchar *end;
    guint64 value = g_ascii_strtoull(target, &end, 10);
    if (!*target || *end || !value || value > G_MAXUINT) {
      g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_INVALID_ARGUMENT, "Attach requires a running PID");
      return FALSE;
    }
    pid = (guint)value;
  }
  session = frida_device_attach_sync(device, pid, NULL, operation, error);
  if (!session) return FALSE;
  g_signal_connect(session, "detached", G_CALLBACK(detached), NULL);
  if (frida_session_is_detached(session)) {
    g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_CLOSED, "Target detached before script loading");
    return FALSE;
  }
  if (*source && !load(source, error)) return FALSE;
  if (spawned_pid) {
    frida_device_resume_sync(device, pid, operation, error);
    if (*error) return FALSE;
    spawned_pid = 0;
  }
  emit("attached", frida_version_string(), pid);
  return TRUE;
}

static gboolean input(GIOChannel *channel, GIOCondition condition, gpointer unused) {
  gchar *line = NULL;
  GError *error = NULL;
  GIOStatus status = g_io_channel_read_line(channel, &line, NULL, NULL, &error);
  if (status == G_IO_STATUS_AGAIN) return G_SOURCE_CONTINUE;
  if (status != G_IO_STATUS_NORMAL) {
    g_clear_error(&error);
    g_free(line);
    g_main_loop_quit(loop);
    return G_SOURCE_REMOVE;
  }
  JsonParser *parser = json_parser_new();
  gboolean valid = strlen(line) <= 4 * 1024 * 1024 && json_parser_load_from_data(parser, line, -1, NULL);
  JsonNode *root = valid ? json_parser_get_root(parser) : NULL;
  JsonObject *command = root && JSON_NODE_HOLDS_OBJECT(root) ? json_node_get_object(root) : NULL;
  const gchar *operation = command ? text(command, "command") : NULL;
  VPhoneOperation *timer = begin_operation(15);
  gboolean keep = TRUE;
  if (operation && !strcmp(operation, "start") && !device && !session) {
    if (!start(command, &error)) keep = FALSE;
    if (text(command, "mode") && !strcmp(text(command, "mode"), "probe")) keep = FALSE;
  } else if (operation && !strcmp(operation, "load") && session && !frida_session_is_detached(session)) {
    const gchar *source = text(command, "source");
    if (!source || !*source) {
      emit("error", "Select a nonempty JavaScript file", 0);
    } else if (load(source, &error)) {
      emit("loaded", "Script loaded", 0);
    }
  } else if (operation && !strcmp(operation, "detach")) {
    keep = FALSE;
  } else {
    emit("error", "Invalid command or session state", 0);
  }
  if (error) { emit("error", error->message, 0); g_error_free(error); }
  end_operation(timer);
  g_object_unref(parser);
  g_free(line);
  if (!keep) g_main_loop_quit(loop);
  return keep ? G_SOURCE_CONTINUE : G_SOURCE_REMOVE;
}

int main(int argc, char **argv) {
  if (argc == 2 && !strcmp(argv[1], "--version")) {
    puts(frida_version_string());
    return 0;
  }
  if (argc != 1) return 2;
  signal(SIGPIPE, SIG_IGN);
  frida_init();
  loop = g_main_loop_new(NULL, FALSE);
  manager = frida_device_manager_new();
  GIOChannel *channel = g_io_channel_unix_new(STDIN_FILENO);
  g_io_channel_set_encoding(channel, NULL, NULL);
  g_io_channel_set_flags(channel, G_IO_FLAG_NONBLOCK, NULL);
  g_io_add_watch(channel, G_IO_IN | G_IO_HUP | G_IO_ERR, input, NULL);
  emit("ready", frida_version_string(), 0);
  g_main_loop_run(loop);
  stopping = TRUE;
  VPhoneOperation *timer = begin_operation(5);
  if (script) { frida_script_unload_sync(script, operation, NULL); g_object_unref(script); }
  if (session) { frida_session_detach_sync(session, operation, NULL); g_object_unref(session); }
  end_operation(timer);
  // Only a spawn that never reached resume is ours to terminate.
  if (spawned_pid && device) {
    GError *error = NULL;
    timer = begin_operation(5);
    frida_device_kill_sync(device, spawned_pid, operation, &error);
    if (error) { emit("error", error->message, spawned_pid); g_error_free(error); }
    end_operation(timer);
  }
  if (device) g_object_unref(device);
  timer = begin_operation(3);
  frida_device_manager_close_sync(manager, operation, NULL);
  end_operation(timer);
  g_object_unref(manager);
  g_io_channel_unref(channel);
  g_main_loop_unref(loop);
  emit("closed", "Session detached", 0);
  return 0;
}
