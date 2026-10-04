/* Synthetic memory only: no OS process access and no game integration.
 * A real C FFI call replaces the Lua per-byte dictionary in the old fixture.
 */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#define SLOTS 32768
typedef struct Page { uintptr_t key; unsigned char bytes[4096], valid[4096]; } Page;
static Page *pages[SLOTS];
/* 1: a page holding fixture data is readable as a whole, as real memory is. */
static int page_mode;
void qa_page_mode(int enabled) { page_mode = enabled; }
static Page *page(uintptr_t address, int create) {
    uintptr_t key = address >> 12;
    size_t h = (key * 2654435761u) & (SLOTS - 1);
    for (size_t i = 0; i < SLOTS; ++i, h = (h + 1) & (SLOTS - 1)) {
        if (!pages[h]) {
            if (!create) return NULL;
            pages[h] = calloc(1, sizeof(Page));
            if (!pages[h]) abort();
            pages[h]->key = key;
        }
        if (pages[h]->key == key) return pages[h];
    }
    abort();
}
void qa_reset(void) {
    for (size_t i = 0; i < SLOTS; ++i) { free(pages[i]); pages[i] = NULL; }
}
void qa_put(uintptr_t at, const void *data, size_t n) {
    const unsigned char *src = data;
    while (n) {
        Page *p = page(at, 1); size_t offset = at & 4095;
        size_t amount = n < 4096 - offset ? n : 4096 - offset;
        memcpy(p->bytes + offset, src, amount); memset(p->valid + offset, 1, amount);
        at += amount; src += amount; n -= amount;
    }
}
int qa_read(void *ignored, const void *address, void *out, size_t n, size_t *count) {
    (void)ignored;
    uintptr_t at = (uintptr_t)address; unsigned char *dest = out; size_t total = n;
    *count = 0;
    while (n) {
        Page *p = page(at, 0); size_t offset = at & 4095;
        size_t amount = n < 4096 - offset ? n : 4096 - offset;
        if (!p || (!page_mode && memchr(p->valid + offset, 0, amount))) return 0;
        memcpy(dest, p->bytes + offset, amount);
        at += amount; dest += amount; n -= amount;
    }
    *count = total; return 1;
}
