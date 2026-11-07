// Test-only Frida boundary: deterministic failures exercise the real client's
// pipe protocol and cleanup without injecting into a host or guest process.
#include "frida-core.h"
#include <stdio.h>

static void trace(const char *name) { printf("{\"event\":\"trace\",\"message\":\"%s\"}\n", name); fflush(stdout); }
static gboolean fail(const char *step, GError **error) {
  if (g_strcmp0(g_getenv("VPHONE_FRIDA_FAIL"), step)) return FALSE;
  g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_FAILED, "Injected lifecycle failure");
  return TRUE;
}
FridaProcessList *vp_test_processes(FridaDevice *d, FridaProcessQueryOptions *o, GCancellable *c, GError **e) {
  trace("enumerate");
  return fail("enumerate",e) ? NULL : (FridaProcessList *)g_object_new(G_TYPE_OBJECT,NULL);
}
gint vp_test_process_count(FridaProcessList *p) { return !g_strcmp0(g_getenv("VPHONE_FRIDA_FAIL"),"multiple") ? 2 : 1; }
FridaProcess *vp_test_process(FridaProcessList *p,gint index) { return (FridaProcess *)g_object_new(G_TYPE_OBJECT,NULL); }
const gchar *vp_test_process_name(FridaProcess *p) { return !g_strcmp0(g_getenv("VPHONE_FRIDA_FAIL"),"wrong-name") ? "Other" : "Gadget"; }
guint vp_test_process_pid(FridaProcess *p) { return 4242; }
FridaDevice *vp_test_remote(FridaDeviceManager *m, const gchar *address, FridaRemoteDeviceOptions *o, GCancellable *c, GError **e) {
  trace("connect");
  if (!g_strcmp0(g_getenv("VPHONE_FRIDA_FAIL"), "timeout")) {
    while (!g_cancellable_is_cancelled(c)) g_usleep(10000);
    g_cancellable_set_error_if_cancelled(c, e);
    return NULL;
  }
  return fail("connect", e) ? NULL : (FridaDevice *)g_object_new(G_TYPE_OBJECT, NULL);
}
guint vp_test_spawn(FridaDevice *d, const gchar *p, FridaSpawnOptions *o, GCancellable *c, GError **e) {
  trace("spawn"); return fail("spawn", e) ? 0 : 4242;
}
FridaSession *vp_test_attach(FridaDevice *d, guint pid, FridaSessionOptions *o, GCancellable *c, GError **e) {
  trace("attach");
  if (fail("attach", e)) return NULL;
  g_signal_new("detached", G_TYPE_OBJECT, G_SIGNAL_RUN_LAST, 0, NULL, NULL, NULL,
               G_TYPE_NONE, 2, FRIDA_TYPE_SESSION_DETACH_REASON, G_TYPE_POINTER);
  return (FridaSession *)g_object_new(G_TYPE_OBJECT, NULL);
}
gboolean vp_test_is_detached(FridaSession *s) { return FALSE; }
FridaScript *vp_test_create(FridaSession *s, const gchar *source, FridaScriptOptions *o, GCancellable *c, GError **e) {
  trace("compile");
  if (fail("compile", e)) return NULL;
  if (!strcmp(source, "invalid")) {
    g_set_error_literal(e, G_IO_ERROR, G_IO_ERROR_FAILED, "Invalid script syntax");
    return NULL;
  }
  if (!g_signal_lookup("message", G_TYPE_OBJECT))
    g_signal_new("message", G_TYPE_OBJECT, G_SIGNAL_RUN_LAST, 0, NULL, NULL, NULL,
                 G_TYPE_NONE, 2, G_TYPE_STRING, G_TYPE_POINTER);
  return (FridaScript *)g_object_new(G_TYPE_OBJECT, NULL);
}
void vp_test_load(FridaScript *s, GCancellable *c, GError **e) {
  trace("load");
  if (!fail("load", e)) g_signal_emit_by_name(s, "message", "{\"type\":\"log\",\"payload\":\"PROBE_OK\"}", NULL);
}
void vp_test_unload(FridaScript *s, GCancellable *c, GError **e) { trace("unload"); }
void vp_test_resume(FridaDevice *d, guint pid, GCancellable *c, GError **e) { trace("resume"); fail("resume", e); }
void vp_test_kill(FridaDevice *d, guint pid, GCancellable *c, GError **e) { trace("kill-unresumed-spawn"); }
void vp_test_detach(FridaSession *s, GCancellable *c, GError **e) { trace("detach"); }
