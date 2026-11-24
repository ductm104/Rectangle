#include <ApplicationServices/ApplicationServices.h>
#include <assert.h>
#include <stdio.h>

static unsigned int postedEvents;
static void record_event(CGEventTapProxy proxy, CGEventRef event) {
    (void)proxy;
    assert(CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode) == 53);
    assert(CGEventGetFlags(event) == 0);
    assert(CGEventGetType(event) == (postedEvents == 0 ? kCGEventKeyDown : kCGEventKeyUp));
    postedEvents++;
}

#define CGEventTapPostEvent record_event
#include "../Rectangle/InstantSpaces/ISS.c"
#undef CGEventTapPostEvent

static unsigned int callbackCount;
static bool replaceCommit;
static uint32_t lastForwardTabs;
static bool prepare_switch(uint32_t forwardTabs) {
    lastForwardTabs = forwardTabs;
    callbackCount++;
    return replaceCommit;
}

static void send_key(CGEventType type, CGKeyCode key, CGEventFlags flags) {
    CGEventRef event = CGEventCreateKeyboardEvent(NULL, key, type != kCGEventKeyUp);
    CGEventSetType(event, type);
    CGEventSetFlags(event, flags);
    assert(keyTapCallback(NULL, type, event, NULL) == event);
    CFRelease(event);
}

static CFArrayRef numbers(const int *values, CFIndex count) {
    CFMutableArrayRef array = CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks);
    for (CFIndex i = 0; i < count; i++) {
        CFNumberRef value = CFNumberCreate(NULL, kCFNumberIntType, &values[i]);
        CFArrayAppendValue(array, value);
        CFRelease(value);
    }
    return array;
}

static void test_window_targets(void) {
    int ids[] = {3, 17, 42};
    CFArrayRef spaceIDs = numbers(ids, 3);
    CFMutableArrayRef spaces = CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks);
    for (CFIndex i = 0; i < 3; i++) {
        const void *key = CFSTR("id64");
        const void *value = CFArrayGetValueAtIndex(spaceIDs, i);
        CFDictionaryRef space = CFDictionaryCreate(NULL, &key, &value, 1,
                                                   &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        CFArrayAppendValue(spaces, space);
        CFRelease(space);
    }
    const void *keys[] = { CFSTR("Display Identifier"), CFSTR("Spaces") };
    const void *values[] = { CFSTR("display-a"), spaces };
    CFDictionaryRef display = CFDictionaryCreate(NULL, keys, values, 2,
                                                 &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFArrayRef displays = CFArrayCreate(NULL, (const void **)&display, 1, &kCFTypeArrayCallBacks);
    ISSSpaceInfo info = {.currentIndex = 1, .spaceCount = 3};
    strcpy(info.displayID, "display-a");
    unsigned int target = 99;
    for (int i = 0; i < 3; i++) {
        CFArrayRef windowSpaces = numbers(&ids[i], 1);
        assert(window_space_target(displays, windowSpaces, &info, &target) == (i != 1));
        assert(target == (unsigned int)i);
        CFRelease(windowSpaces);
    }
    CFArrayRef sticky = numbers(ids, 3);
    assert(!window_space_target(displays, sticky, &info, &target));
    CFRelease(sticky);
    CFArrayRef empty = numbers(NULL, 0);
    assert(!window_space_target(displays, empty, &info, &target));
    CFRelease(empty);
    int unknownID = 999;
    CFArrayRef unknown = numbers(&unknownID, 1);
    assert(!window_space_target(displays, unknown, &info, &target));
    CFRelease(unknown);
    strcpy(info.displayID, "display-b");
    CFArrayRef otherDisplay = numbers(ids, 1);
    assert(!window_space_target(displays, otherDisplay, &info, &target));
    CFRelease(otherDisplay);
    CFRelease(displays);
    CFRelease(display);
    CFRelease(spaces);
    CFRelease(spaceIDs);
}

static void test_cmd_tab_commit(void) {
    iss_set_swipe_override(true);
    iss_set_app_switch_callback(prepare_switch);
    send_key(kCGEventFlagsChanged, kVK_Command, 0);
    assert(callbackCount == 0);
    send_key(kCGEventKeyDown, kVK_Tab, kCGEventFlagMaskCommand);
    send_key(kCGEventFlagsChanged, kVK_Command, 0);
    assert(callbackCount == 1 && postedEvents == 0 && lastForwardTabs == 1);
    replaceCommit = true;
    send_key(kCGEventKeyDown, kVK_Tab, kCGEventFlagMaskCommand | kCGEventFlagMaskShift);
    send_key(kCGEventFlagsChanged, kVK_Command, kCGEventFlagMaskCommand);
    assert(callbackCount == 1);
    send_key(kCGEventFlagsChanged, kVK_Command, 0);
    assert(callbackCount == 2 && postedEvents == 2 && lastForwardTabs == 0);
    send_key(kCGEventFlagsChanged, kVK_Command, 0);
    assert(callbackCount == 2);
    send_key(kCGEventKeyDown, kVK_Tab, kCGEventFlagMaskCommand);
    send_key(kCGEventKeyDown, kVK_Escape, kCGEventFlagMaskCommand);
    send_key(kCGEventFlagsChanged, kVK_Command, 0);
    assert(callbackCount == 2);
    send_key(kCGEventKeyDown, kVK_Tab, kCGEventFlagMaskCommand);
    iss_set_swipe_override(false);
    send_key(kCGEventFlagsChanged, kVK_Command, 0);
    assert(callbackCount == 2);
    iss_set_swipe_override(true);
    replaceCommit = false;
    send_key(kCGEventKeyDown, kVK_Tab, kCGEventFlagMaskCommand);
    send_key(kCGEventKeyDown, kVK_Tab, kCGEventFlagMaskCommand);
    send_key(kCGEventFlagsChanged, kVK_Command, 0);
    assert(callbackCount == 3 && lastForwardTabs == 2);
    send_key(kCGEventKeyDown, kVK_Tab, kCGEventFlagMaskCommand);
    send_key(kCGEventKeyDown, kVK_LeftArrow, kCGEventFlagMaskCommand);
    send_key(kCGEventFlagsChanged, kVK_Command, 0);
    assert(callbackCount == 4 && lastForwardTabs == 0);
    send_key(kCGEventKeyDown, kVK_Tab, kCGEventFlagMaskCommand);
    CGEventRef click = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDown, CGPointZero, kCGMouseButtonLeft);
    assert(keyTapCallback(NULL, kCGEventLeftMouseDown, click, NULL) == click);
    CFRelease(click);
    send_key(kCGEventFlagsChanged, kVK_Command, 0);
    assert(callbackCount == 4);
    send_key(kCGEventKeyDown, kVK_Tab, kCGEventFlagMaskCommand);
    send_key(kCGEventKeyDown, kVK_Tab, kCGEventFlagMaskCommand);
    send_key(kCGEventKeyDown, kVK_Tab, kCGEventFlagMaskCommand);
    send_key(kCGEventFlagsChanged, kVK_Command, 0);
    assert(callbackCount == 5 && lastForwardTabs == 3);
    send_key(kCGEventKeyDown, kVK_Tab, kCGEventFlagMaskCommand | kCGEventFlagMaskShift);
    send_key(kCGEventKeyDown, kVK_Tab, kCGEventFlagMaskCommand);
    send_key(kCGEventFlagsChanged, kVK_Command, 0);
    assert(callbackCount == 6 && lastForwardTabs == 0);
    iss_destroy();
    assert(appSwitchCallback == NULL);
}

int main(void) {
    test_window_targets();
    test_cmd_tab_commit();
    puts("Instant Spaces tests passed");
    return 0;
}
