#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
@interface FixtureScene : UIResponder <UIWindowSceneDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation FixtureScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    BOOL loaded = NO;
    for (uint32_t i=0; i<_dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name,"FridaGadget.dylib")) loaded = YES;
    }
    NSDictionary *result = @{ @"gadgetLoaded":@(loaded), @"fixture":@"com.vphone.fixture.gadget" };
    NSData *json = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
    NSString *documents = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
    [[NSFileManager defaultManager] createDirectoryAtPath:documents withIntermediateDirectories:YES attributes:nil error:nil];
    [json writeToFile:[documents stringByAppendingPathComponent:@"gadget-fixture.json"] atomically:YES];
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    UIViewController *controller = [UIViewController new];
    controller.view.backgroundColor = UIColor.systemBackgroundColor;
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(16,100,600,80)];
    label.text = loaded ? @"Frida Gadget loaded" : @"Gadget not loaded";
    label.font = [UIFont systemFontOfSize:28];
    [controller.view addSubview:label]; self.window.rootViewController = controller;
    [self.window makeKeyAndVisible];
}
@end
@interface FixtureDelegate : UIResponder <UIApplicationDelegate>
@end
@implementation FixtureDelegate
- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *configuration = [[UISceneConfiguration alloc] initWithName:@"Fixture" sessionRole:session.role];
    configuration.delegateClass = FixtureScene.class; return configuration;
}
@end
int main(int argc,char **argv) { @autoreleasepool { return UIApplicationMain(argc,argv,nil,NSStringFromClass(FixtureDelegate.class)); } }
