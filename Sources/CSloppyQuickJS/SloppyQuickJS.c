#include "SloppyQuickJS.h"
#include "quickjs.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

struct SloppyQuickJS {
    JSRuntime *runtime;
    JSContext *context;
    JSValue step;
    int64_t deadline_ms;
    int64_t slice_deadline_ms;
    char error[1024];
};

static int64_t monotonic_ms(void) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (int64_t)now.tv_sec * 1000 + now.tv_nsec / 1000000;
}

static int deadline_reached(JSRuntime *runtime, void *opaque) {
    (void)runtime;
    SloppyQuickJS *vm = opaque;
    int64_t now = monotonic_ms();
    return now >= vm->deadline_ms || now >= vm->slice_deadline_ms;
}

static void enter_vm(SloppyQuickJS *vm) {
    vm->slice_deadline_ms = monotonic_ms() + 2000;
    JS_UpdateStackTop(vm->runtime);
}

static int record_error(SloppyQuickJS *vm, JSContext *context) {
    JSValue exception = JS_GetException(context);
    const char *message = JS_ToCString(context, exception);
    snprintf(vm->error, sizeof(vm->error), "%s", deadline_reached(NULL, vm)
        ? "JavaScript exceeded its execution time limit"
        : (message ? message : "QuickJS execution failed"));
    if (message) JS_FreeCString(context, message);
    JS_FreeValue(context, exception);
    return -1;
}

SloppyQuickJS *sloppy_js_create(int timeout_ms) {
    SloppyQuickJS *vm = calloc(1, sizeof(*vm));
    if (!vm) return NULL;
    vm->runtime = JS_NewRuntime();
    if (!vm->runtime) {
        free(vm);
        return NULL;
    }
    vm->deadline_ms = monotonic_ms() + timeout_ms;
    JS_SetMemoryLimit(vm->runtime, 16 * 1024 * 1024);
    JS_SetMaxStackSize(vm->runtime, 256 * 1024);
    JS_SetInterruptHandler(vm->runtime, deadline_reached, vm);
    JS_SetCanBlock(vm->runtime, 0);
    enter_vm(vm);
    vm->context = JS_NewContext(vm->runtime);
    vm->step = JS_UNDEFINED;
    if (!vm->context) {
        sloppy_js_destroy(vm);
        return NULL;
    }
    return vm;
}

void sloppy_js_destroy(SloppyQuickJS *vm) {
    JS_UpdateStackTop(vm->runtime);
    if (vm->context) {
        JS_FreeValue(vm->context, vm->step);
        JS_FreeContext(vm->context);
    }
    JS_FreeRuntime(vm->runtime);
    free(vm);
}

int sloppy_js_start(SloppyQuickJS *vm, const char *bootstrap, const char *input, const char *script) {
    enter_vm(vm);
    JSContext *ctx = vm->context;
    JSValue factory = JS_Eval(ctx, bootstrap, strlen(bootstrap), "codemode-bridge.js", JS_EVAL_TYPE_GLOBAL);
    if (JS_IsException(factory)) return record_error(vm, ctx);

    JSValue args[] = { JS_NewString(ctx, input), JS_NewString(ctx, script) };
    vm->step = JS_Call(ctx, factory, JS_UNDEFINED, 2, args);
    JS_FreeValue(ctx, args[0]);
    JS_FreeValue(ctx, args[1]);
    JS_FreeValue(ctx, factory);
    return JS_IsException(vm->step) ? record_error(vm, ctx) : 0;
}

char *sloppy_js_step(SloppyQuickJS *vm, const char *completion) {
    enter_vm(vm);
    JSContext *ctx = vm->context;
    JSValue args[] = { JS_NewString(ctx, completion), JS_NewBool(ctx, completion[0] == '\0') };
    JSValue state = JS_Call(ctx, vm->step, JS_UNDEFINED, 2, args);
    JS_FreeValue(ctx, args[0]);
    if (JS_IsException(state)) {
        record_error(vm, ctx);
        return NULL;
    }

    const char *text = JS_ToCString(ctx, state);
    char *copy = text ? strdup(text) : NULL;
    if (text) JS_FreeCString(ctx, text);
    JS_FreeValue(ctx, state);
    return copy;
}

int sloppy_js_pump(SloppyQuickJS *vm) {
    enter_vm(vm);
    JSContext *job_context;
    while (!deadline_reached(NULL, vm)) {
        int result = JS_ExecutePendingJob(vm->runtime, &job_context);
        if (result < 0) return record_error(vm, job_context);
        if (result == 0) return 0;
    }
    snprintf(vm->error, sizeof(vm->error), "JavaScript exceeded its execution time limit");
    return -1;
}

const char *sloppy_js_error(const SloppyQuickJS *vm) {
    return vm->error[0] ? vm->error : "QuickJS execution failed";
}

void sloppy_js_free_string(char *text) {
    free(text);
}
