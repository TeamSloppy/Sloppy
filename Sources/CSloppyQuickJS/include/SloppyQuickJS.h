#ifndef SLOPPY_QUICK_JS_H
#define SLOPPY_QUICK_JS_H

#include <stddef.h>

typedef struct SloppyQuickJS SloppyQuickJS;

SloppyQuickJS *sloppy_js_create(int timeout_ms);
void sloppy_js_destroy(SloppyQuickJS *vm);
int sloppy_js_start(SloppyQuickJS *vm, const char *bootstrap, const char *input, const char *script);
char *sloppy_js_step(SloppyQuickJS *vm, const char *completion);
int sloppy_js_pump(SloppyQuickJS *vm);
const char *sloppy_js_error(const SloppyQuickJS *vm);
void sloppy_js_free_string(char *text);

#endif
