// In-process GDExtension: controls only windows owned by this Godot process.
// No Accessibility permission, screen capture, wallpaper writes or window injection.
#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#include <sys/file.h>
#include <fcntl.h>
#include <unistd.h>
#include "vendor/gdextension_interface.h"

@interface TownDesktopState : NSObject
@property(nonatomic, weak) NSWindow *desktop;
@property(nonatomic, weak) NSWindow *manager;
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) NSMenuItem *appMenuItem;
@property(nonatomic, strong) NSMenuItem *quitItem;
@property(nonatomic, strong) id originalQuitTarget;
@property(nonatomic) SEL originalQuitAction;
@property(nonatomic) NSInteger originalQuitTag;
@property(nonatomic, strong) id screenObserver;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *events;
@property(nonatomic) uint32_t preferredDisplay;
@property(nonatomic) BOOL enabled;
@property(nonatomic) int clockFD;
- (NSDictionary *)command:(int64_t)operation value:(int64_t)value;
- (void)cleanup;
@end

static NSWindow *ownedWindow(int64_t handle) {
    // Do not dereference an untrusted pointer. Match against our own window list.
    for (NSWindow *window in NSApp.windows)
        if ((uintptr_t)(__bridge void *)window == (uintptr_t)handle) return window;
    return nil;
}
static uint32_t displayID(NSScreen *screen) {
    return [screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
}

@implementation TownDesktopState
- (instancetype)init {
    if ((self=[super init])) { _clockFD=-1; _events=[NSMutableArray new]; }
    return self;
}
- (NSScreen *)targetScreen {
    for (NSScreen *screen in NSScreen.screens)
        if (displayID(screen)==self.preferredDisplay) return screen;
    return NSScreen.screens.firstObject ?: NSScreen.mainScreen;
}
- (void)positionDesktop {
    NSWindow *window=self.desktop;
    NSScreen *screen=[self targetScreen];
    if (!window || !screen) return;
    window.opaque=NO; window.backgroundColor=NSColor.clearColor;
    window.hasShadow=NO; window.ignoresMouseEvents=YES;
    window.acceptsMouseMovedEvents=NO; window.hidesOnDeactivate=NO;
    window.movable=NO; window.restorable=NO;
    window.collectionBehavior=NSWindowCollectionBehaviorCanJoinAllSpaces |
        NSWindowCollectionBehaviorStationary | NSWindowCollectionBehaviorIgnoresCycle;
    window.level=MIN(CGWindowLevelForKey(kCGDesktopWindowLevelKey)+1,
                     CGWindowLevelForKey(kCGDesktopIconWindowLevelKey)-1);
    [window setFrame:screen.frame display:YES];
    if (self.enabled) [window orderFront:nil]; else [window orderOut:nil];
}
- (void)menuAction:(NSMenuItem *)sender { [self.events addObject:@(sender.tag)]; }
- (void)installMenu {
    if (self.statusItem) return;
    self.statusItem=[NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.title=@"小城";
    self.statusItem.button.toolTip=@"小城志 · 桌面与管理窗口共用一座城";
    NSMenu *menu=[NSMenu new];
    NSArray *titles=@[@"打开城务窗口",@"酒馆招募",@"武将培养",@"天下战役",@"显示 / 隐藏桌面小城",@"暂停 / 继续经营",@"退出小城志"];
    for (NSUInteger i=0;i<titles.count;i++) {
        if (i==4 || i==6) [menu addItem:NSMenuItem.separatorItem];
        NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:titles[i] action:@selector(menuAction:) keyEquivalent:@""];
        item.tag=i+1; item.target=self; [menu addItem:item];
    }
    self.statusItem.menu=menu;
    self.appMenuItem=[[NSMenuItem alloc] initWithTitle:@"小城" action:nil keyEquivalent:@""];
    self.appMenuItem.submenu=[menu copy];
    [NSApp.mainMenu insertItem:self.appMenuItem atIndex:MIN(1,NSApp.mainMenu.numberOfItems)];
    // Closing a management window hides it, but Cmd-Q must still genuinely quit.
    for (NSMenuItem *top in NSApp.mainMenu.itemArray) {
        for (NSMenuItem *item in top.submenu.itemArray) {
            if ([item.keyEquivalent isEqualToString:@"q"] && (item.keyEquivalentModifierMask & NSEventModifierFlagCommand)) {
                self.quitItem=item; self.originalQuitAction=item.action; self.originalQuitTarget=item.target; self.originalQuitTag=item.tag;
                item.target=self; item.action=@selector(menuAction:); item.tag=7;
            }
        }
    }
}
- (NSDictionary *)status {
    NSMutableArray *screens=[NSMutableArray new];
    for (NSScreen *screen in NSScreen.screens) {
        NSRect f=screen.frame;
        [screens addObject:@{@"id":@(displayID(screen)),@"name":screen.localizedName,
            @"x":@(f.origin.x),@"y":@(f.origin.y),@"width":@(f.size.width),@"height":@(f.size.height)}];
    }
    NSWindow *window=self.desktop;
    NSRect frame=window ? window.frame : NSZeroRect;
    return @{@"ok":@YES,@"enabled":@(self.enabled),@"visible":@(window.isVisible),
        @"mouse_passthrough":@(window.ignoresMouseEvents),@"opaque":@(window.isOpaque),
        @"can_become_key":@(window.canBecomeKeyWindow),@"level":@(window.level),
        @"normal_level":@(NSNormalWindowLevel),@"icon_level":@(CGWindowLevelForKey(kCGDesktopIconWindowLevelKey)),
        @"preferred_display":@(self.preferredDisplay),@"active_display":@(displayID([self targetScreen])),
        @"frame":@[@(frame.origin.x),@(frame.origin.y),@(frame.size.width),@(frame.size.height)],
        @"screens":screens,@"clock_owner":@(self.clockFD>=0),@"menu_installed":@(self.statusItem!=nil)};
}
- (NSDictionary *)command:(int64_t)operation value:(int64_t)value {
    if (!NSThread.isMainThread) return @{@"ok":@NO,@"error":@"Desktop calls require the main thread"};
    switch (operation) {
        case 0: { // Attach a Godot-owned native, unfocusable, transparent Window.
            NSWindow *window=ownedWindow(value);
            if (!window || window==self.manager) return @{@"ok":@NO,@"error":@"Invalid desktop window"};
            self.desktop=window; self.enabled=YES;
            if (!self.screenObserver) {
                __weak TownDesktopState *weakSelf=self;
                self.screenObserver=[NSNotificationCenter.defaultCenter addObserverForName:NSApplicationDidChangeScreenParametersNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { [weakSelf positionDesktop]; }];
            }
            [self positionDesktop]; break;
        }
        case 1: break; // Read diagnostics, including actual AppKit window flags.
        case 2: self.preferredDisplay=(uint32_t)value; [self positionDesktop]; break;
        case 3: self.enabled=value!=0; [self positionDesktop]; break;
        case 4: {
            NSNumber *event=self.events.firstObject ?: @0;
            if (self.events.count) [self.events removeObjectAtIndex:0];
            return @{@"ok":@YES,@"event":event};
        }
        case 5:
            self.manager=ownedWindow(value);
            if (!self.manager) return @{@"ok":@NO,@"error":@"Invalid manager window"};
            [self installMenu]; break;
        case 6: [self cleanup]; break;
        case 7:
            if (value) { [self.manager makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES]; }
            else [self.manager orderOut:nil];
            break;
        case 9: { // A long-lived lock: two frontends must never run two city clocks.
            if (self.clockFD>=0) break;
            const char *fixture=getenv("SANGUO_GODOT_SAVE");
            NSString *directory=fixture && fixture[0] ? @(fixture) : [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/SanguoTown-HeroTown09"];
            NSString *name=directory.lastPathComponent;
            if (![name isEqualToString:@"SanguoTown-HeroTown09"] && ![name isEqualToString:@"SanguoTown-GodotPreview"] && ![name hasPrefix:@"godot-fixture-"])
                return @{@"ok":@NO,@"error":@"Invalid independent save directory"};
            NSError *error=nil;
            if (![NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error])
                return @{@"ok":@NO,@"error":error.localizedDescription};
            int fd=open([[directory stringByAppendingPathComponent:@"frontend.lock"] fileSystemRepresentation],O_CREAT|O_RDWR,0600);
            if (fd<0 || flock(fd,LOCK_EX|LOCK_NB)!=0) {
                if (fd>=0) close(fd);
                return @{@"ok":@NO,@"error":@"这座小城已在另一个窗口运行，请从菜单栏「小城」打开，避免重复经营。"};
            }
            self.clockFD=fd; break;
        }
        default: return @{@"ok":@NO,@"error":@"Unknown desktop command"};
    }
    return [self status];
}
- (void)cleanup {
    [self.desktop orderOut:nil]; self.desktop=nil; self.enabled=NO;
    if (self.screenObserver) [NSNotificationCenter.defaultCenter removeObserver:self.screenObserver];
    self.screenObserver=nil;
    if (self.statusItem) [NSStatusBar.systemStatusBar removeStatusItem:self.statusItem];
    self.statusItem=nil;
    if (self.appMenuItem) [NSApp.mainMenu removeItem:self.appMenuItem];
    self.appMenuItem=nil;
    if (self.quitItem) { self.quitItem.action=self.originalQuitAction; self.quitItem.target=self.originalQuitTarget; self.quitItem.tag=self.originalQuitTag; }
    self.quitItem=nil; self.originalQuitTarget=nil;
    if (self.clockFD>=0) { flock(self.clockFD,LOCK_UN); close(self.clockFD); self.clockFD=-1; }
}
@end

// Small C ABI binding; no C++ runtime or Godot engine rebuild required.
typedef struct { uint64_t opaque; } GodotString;
typedef struct { GDExtensionObjectPtr object; void *state; } Host;
static GDExtensionClassLibraryPtr library;
static GDExtensionInterfaceClassdbConstructObject constructObject;
static GDExtensionInterfaceObjectSetInstance setInstance;
static GDExtensionInterfaceStringNameNewWithLatin1Chars makeName;
static GDExtensionInterfaceStringNewWithUtf8Chars makeString;
static GDExtensionInterfaceClassdbRegisterExtensionClass2 registerClass;
static GDExtensionInterfaceClassdbRegisterExtensionClassMethod registerMethod;
static GDExtensionInterfaceClassdbUnregisterExtensionClass unregisterClass;
static GDExtensionPtrDestructor destroyName, destroyString;
static GDExtensionTypeFromVariantConstructorFunc readInt;
static GDExtensionVariantFromTypeConstructorFunc returnString;
static GDExtensionObjectPtr createHost(void *unused) {
    GodotString base, name; makeName(&base,"Object",0); makeName(&name,"TownDesktopHost",0);
    Host *host=calloc(1,sizeof(Host)); host->object=constructObject(&base);
    host->state=(__bridge_retained void *)[TownDesktopState new];
    setInstance(host->object,&name,host); destroyName(&base); destroyName(&name);
    return host->object;
}
static void freeHost(void *unused,GDExtensionClassInstancePtr instance) {
    Host *host=instance;
    if (!host) return;
    TownDesktopState *state=(__bridge_transfer TownDesktopState *)host->state;
    [state cleanup]; free(host);
}
static NSString *execute(Host *host,int64_t operation,int64_t value) {
    TownDesktopState *state=(__bridge TownDesktopState *)host->state;
    NSData *json=[NSJSONSerialization dataWithJSONObject:[state command:operation value:value] options:0 error:nil];
    return [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
}
static void callCommand(void *unused,GDExtensionClassInstancePtr instance,const GDExtensionConstVariantPtr *args,GDExtensionInt count,GDExtensionVariantPtr result,GDExtensionCallError *error) {
    GodotString value;
    if (count!=2) {
        error->error=GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT;
        makeString(&value,"{\"ok\":false,\"error\":\"Expected operation and value\"}");
    } else {
        int64_t operation=0,parameter=0; readInt(&operation,(GDExtensionVariantPtr)args[0]); readInt(&parameter,(GDExtensionVariantPtr)args[1]);
        makeString(&value,execute(instance,operation,parameter).UTF8String); error->error=GDEXTENSION_CALL_OK;
    }
    returnString(result,&value); destroyString(&value);
}
static void ptrCommand(void *unused,GDExtensionClassInstancePtr instance,const GDExtensionConstTypePtr *args,GDExtensionTypePtr result) {
    makeString(result,execute(instance,*(int64_t *)args[0],*(int64_t *)args[1]).UTF8String);
}
static void initialize(void *unused,GDExtensionInitializationLevel level) {
    if (level!=GDEXTENSION_INITIALIZATION_SCENE) return;
    GodotString name,base,method,empty,arg0,arg1,hint;
    makeName(&name,"TownDesktopHost",0); makeName(&base,"Object",0); makeName(&method,"command",0);
    makeName(&empty,"",0); makeName(&arg0,"operation",0); makeName(&arg1,"value",0); makeString(&hint,"");
    GDExtensionClassCreationInfo2 info={0}; info.is_exposed=1; info.create_instance_func=createHost; info.free_instance_func=freeHost;
    registerClass(library,&name,&base,&info);
    GDExtensionPropertyInfo output={GDEXTENSION_VARIANT_TYPE_STRING,&empty,&empty,0,&hint,6};
    GDExtensionPropertyInfo arguments[2]={{GDEXTENSION_VARIANT_TYPE_INT,&arg0,&empty,0,&hint,6},{GDEXTENSION_VARIANT_TYPE_INT,&arg1,&empty,0,&hint,6}};
    GDExtensionClassMethodArgumentMetadata metadata[2]={GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_INT64,GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_INT64};
    GDExtensionClassMethodInfo binding={0}; binding.name=&method; binding.call_func=callCommand; binding.ptrcall_func=ptrCommand;
    binding.method_flags=GDEXTENSION_METHOD_FLAG_NORMAL; binding.has_return_value=1; binding.return_value_info=&output;
    binding.argument_count=2; binding.arguments_info=arguments; binding.arguments_metadata=metadata;
    registerMethod(library,&name,&binding);
    destroyName(&name); destroyName(&base); destroyName(&method); destroyName(&empty); destroyName(&arg0); destroyName(&arg1); destroyString(&hint);
}
static void deinitialize(void *unused,GDExtensionInitializationLevel level) {
    if (level!=GDEXTENSION_INITIALIZATION_SCENE) return;
    GodotString name; makeName(&name,"TownDesktopHost",0); unregisterClass(library,&name); destroyName(&name);
}
__attribute__((visibility("default"))) GDExtensionBool town_desktop_init(GDExtensionInterfaceGetProcAddress get,GDExtensionClassLibraryPtr owner,GDExtensionInitialization *init) {
    library=owner;
    constructObject=(GDExtensionInterfaceClassdbConstructObject)get("classdb_construct_object");
    setInstance=(GDExtensionInterfaceObjectSetInstance)get("object_set_instance");
    makeName=(GDExtensionInterfaceStringNameNewWithLatin1Chars)get("string_name_new_with_latin1_chars");
    makeString=(GDExtensionInterfaceStringNewWithUtf8Chars)get("string_new_with_utf8_chars");
    registerClass=(GDExtensionInterfaceClassdbRegisterExtensionClass2)get("classdb_register_extension_class2");
    registerMethod=(GDExtensionInterfaceClassdbRegisterExtensionClassMethod)get("classdb_register_extension_class_method");
    unregisterClass=(GDExtensionInterfaceClassdbUnregisterExtensionClass)get("classdb_unregister_extension_class");
    GDExtensionInterfaceVariantGetPtrDestructor destructor=(GDExtensionInterfaceVariantGetPtrDestructor)get("variant_get_ptr_destructor");
    destroyName=destructor(GDEXTENSION_VARIANT_TYPE_STRING_NAME); destroyString=destructor(GDEXTENSION_VARIANT_TYPE_STRING);
    readInt=((GDExtensionInterfaceGetVariantToTypeConstructor)get("get_variant_to_type_constructor"))(GDEXTENSION_VARIANT_TYPE_INT);
    returnString=((GDExtensionInterfaceGetVariantFromTypeConstructor)get("get_variant_from_type_constructor"))(GDEXTENSION_VARIANT_TYPE_STRING);
    init->minimum_initialization_level=GDEXTENSION_INITIALIZATION_SCENE;
    init->initialize=initialize; init->deinitialize=deinitialize; init->userdata=NULL;
    return 1;
}
