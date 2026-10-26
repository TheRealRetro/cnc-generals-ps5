/*
 * C&C Generals PS5 - libc functions the console does not export.
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The SDK's libc headers are FreeBSD's and declare these, but no module a
 * title loads exports them, so a title that calls one fails to link (or,
 * through a stub, calls address 0). They are defined here, in the title,
 * with FreeBSD's semantics. Linked into every title by ps5/tools/link-title.sh.
 *
 * fnmatch is the exception: libScePosixForWebKit's stub defines it, so it is
 * ps5_title_fnmatch here and the link binds fnmatch to it, as with pathconf.
 */
#include <fnmatch.h>
#include <stddef.h>
#include <wchar.h>
#include <wctype.h>

/* <wctype.h> inlines towlower() in C through FreeBSD's rune-locale internals,
 * which the console does not export; libSceLibcInternal exports the function. */
#undef towlower

/* Copy src into dst, at most dstsize - 1 characters, always terminated.
 * Returns the length of src. */
size_t wcslcpy(wchar_t *dst, const wchar_t *src, size_t dstsize)
{
    size_t srclen = 0;
    while (src[srclen] != L'\0')
        srclen++;
    if (dstsize != 0) {
        size_t copylen = srclen < dstsize ? srclen : dstsize - 1;
        for (size_t i = 0; i < copylen; i++)
            dst[i] = src[i];
        dst[copylen] = L'\0';
    }
    return srclen;
}

/* Append src to dst, which holds dstsize characters, always terminated.
 * Returns the length of the string it tried to create. */
size_t wcslcat(wchar_t *dst, const wchar_t *src, size_t dstsize)
{
    size_t dstlen = 0;
    while (dstlen < dstsize && dst[dstlen] != L'\0')
        dstlen++;
    if (dstlen == dstsize) {
        size_t srclen = 0;
        while (src[srclen] != L'\0')
            srclen++;
        return dstsize + srclen;
    }
    return dstlen + wcslcpy(dst + dstlen, src, dstsize - dstlen);
}

int wcsncasecmp(const wchar_t *s1, const wchar_t *s2, size_t n)
{
    for (; n != 0; n--, s1++, s2++) {
        wint_t c1 = towlower((wint_t)*s1);
        wint_t c2 = towlower((wint_t)*s2);
        if (c1 != c2)
            return (int)c1 - (int)c2;
        if (*s1 == L'\0')
            return 0;
    }
    return 0;
}

int wcscasecmp(const wchar_t *s1, const wchar_t *s2)
{
    return wcsncasecmp(s1, s2, (size_t)-1);
}

/* <wctype.h> defines iswascii() as a macro in C; the function is for C++. */
#undef iswascii
int iswascii(wint_t wc)
{
    return (wc & ~(wint_t)0x7F) == 0;
}

static int fold_case(int c, int flags)
{
    return (flags & FNM_CASEFOLD) && c >= 'A' && c <= 'Z' ? c - 'A' + 'a' : c;
}

/* A bracket expression; p is just past its '['. Returns 1 if c matches, 0 if
 * not, and -1 if the expression is unterminated (the '[' is then literal).
 * *end is set past the closing ']'. Ranges and '!'/'^' negation; no [:class:]. */
static int match_bracket(const char *p, int c, int flags, const char **end)
{
    int negate = 0, matched = 0;
    if (*p == '!' || *p == '^') {
        negate = 1;
        p++;
    }
    const char *first = p;
    while (*p != ']' || p == first) {
        if (*p == '\0')
            return -1;
        int lo = (unsigned char)*p++;
        if (lo == '\\' && !(flags & FNM_NOESCAPE)) {
            if (*p == '\0')
                return -1;
            lo = (unsigned char)*p++;
        }
        int hi = lo;
        if (*p == '-' && p[1] != ']' && p[1] != '\0') {
            p++;
            hi = (unsigned char)*p++;
            if (hi == '\\' && !(flags & FNM_NOESCAPE)) {
                if (*p == '\0')
                    return -1;
                hi = (unsigned char)*p++;
            }
        }
        int folded = fold_case(c, flags);
        if ((c >= lo && c <= hi) || (folded >= fold_case(lo, flags) && folded <= fold_case(hi, flags)))
            matched = 1;
    }
    *end = p + 1;
    return matched != negate;
}

/* Whether the pattern element at p matches the character at s; *next is set
 * past the element. leading: s is a period FNM_PERIOD protects. */
static int match_one(const char *p, const char *s, int leading, int flags, const char **next)
{
    int c = (unsigned char)*s;
    int slash = (flags & FNM_PATHNAME) && c == '/';
    if (*p == '?') {
        *next = p + 1;
        return !leading && !slash;
    }
    if (*p == '[') {
        int matched = match_bracket(p + 1, c, flags, next);
        if (matched >= 0)
            return matched && !leading && !slash;
        *next = p + 1;
        return c == '[';
    }
    if (*p == '\\' && !(flags & FNM_NOESCAPE) && p[1] != '\0')
        p++;
    *next = p + 1;
    return fold_case((unsigned char)*p, flags) == fold_case(c, flags);
}

/* fnmatch(3): FNM_NOESCAPE, FNM_PATHNAME, FNM_PERIOD and FNM_CASEFOLD. A '*'
 * backtracks to the last star only, which is exact for glob patterns. */
int ps5_title_fnmatch(const char *pattern, const char *string, int flags)
{
    const char *p = pattern, *s = string;
    const char *star_p = NULL, *star_s = NULL;
    for (;;) {
        int leading = (flags & FNM_PERIOD) && *s == '.' &&
            (s == string || ((flags & FNM_PATHNAME) && s[-1] == '/'));
        if (*p == '*' && !leading) {
            while (*p == '*')
                p++;
            star_p = p;
            star_s = s;
            continue;
        }
        if (*p == '\0' && *s == '\0')
            return 0;
        const char *next = NULL;
        if (*p != '\0' && *s != '\0' && match_one(p, s, leading, flags, &next)) {
            p = next;
            s++;
            continue;
        }
        /* Let the last star take one more character, and retry after it. */
        if (star_p == NULL || *star_s == '\0' || ((flags & FNM_PATHNAME) && *star_s == '/'))
            return FNM_NOMATCH;
        p = star_p;
        s = ++star_s;
    }
}
