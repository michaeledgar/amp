#include <stdio.h>
#include <stdlib.h>
#include "ruby.h"
#include "rubyio.h"

// these defines are taken from the mercurial source. They're relatively standard for
// byte-swapping, but credit goes where credit's due.
#ifdef _WIN32
# ifdef _MSC_VER
/* msvc 6.0 has problems */
#  define inline __inline
typedef unsigned long uint32_t;
typedef unsigned __int64 uint64_t;
# else
#  include <stdint.h>
# endif
static uint32_t ntohl(uint32_t x)
{
	return ((x & 0x000000ffUL) << 24) |
	       ((x & 0x0000ff00UL) <<  8) |
	       ((x & 0x00ff0000UL) >>  8) |
	       ((x & 0xff000000UL) >> 24);
}
#else
/* not windows */
# include <sys/types.h>
# if defined __BEOS__ && !defined __HAIKU__
#  include <ByteOrder.h>
# else
#  include <arpa/inet.h>
# endif
# include <inttypes.h>
#endif


VALUE rb_mAmp, rb_mDiffs, rb_mMercurialPatch;


struct frag {
	uint32_t start, end, len;
	const char *data;
};

struct flist {
	struct frag *base, *head, *tail;
};

static struct flist *lalloc(int size)
{
	struct flist *a = NULL;

	if (size < 1)
		size = 1;

	a = (struct flist *)malloc(sizeof(struct flist));
	if (a) {
		a->base = (struct frag *)malloc(sizeof(struct frag) * size);
		if (a->base) {
			a->head = a->tail = a->base;
			return a;
		}
		free(a);
		a = NULL;
	}
    // if (!PyErr_Occurred())
    //  PyErr_NoMemory();
	return NULL;
}

static void lfree(struct flist *a)
{
	if (a) {
		free(a->base);
		free(a);
	}
}

static int lsize(struct flist *a)
{
	return a->tail - a->head;
}

/* move hunks in source that are less cut to dest, compensating
   for changes in offset. the last hunk may be split if necessary.
*/
static int gather(struct flist *dest, struct flist *src, int cut, int offset)
{
	struct frag *d = dest->tail, *s = src->head;
	int postend, c, l;

	while (s != src->tail) {
		if (s->start + offset >= cut)
			break; /* we've gone far enough */

		postend = offset + s->start + s->len;
		if (postend <= cut) {
			/* save this hunk */
			offset += s->start + s->len - s->end;
			*d++ = *s++;
		}
		else {
			/* break up this hunk */
			c = cut - offset;
			if (s->end < c)
				c = s->end;
			l = cut - offset - s->start;
			if (s->len < l)
				l = s->len;

			offset += s->start + l - c;

			d->start = s->start;
			d->end = c;
			d->len = l;
			d->data = s->data;
			d++;
			s->start = c;
			s->len = s->len - l;
			s->data = s->data + l;

			break;
		}
	}

	dest->tail = d;
	src->head = s;
	return offset;
}

/* like gather, but with no output list */
static int discard(struct flist *src, int cut, int offset)
{
	struct frag *s = src->head;
	int postend, c, l;

	while (s != src->tail) {
		if (s->start + offset >= cut)
			break;

		postend = offset + s->start + s->len;
		if (postend <= cut) {
			offset += s->start + s->len - s->end;
			s++;
		}
		else {
			c = cut - offset;
			if (s->end < c)
				c = s->end;
			l = cut - offset - s->start;
			if (s->len < l)
				l = s->len;

			offset += s->start + l - c;
			s->start = c;
			s->len = s->len - l;
			s->data = s->data + l;

			break;
		}
	}

	src->head = s;
	return offset;
}

/* combine hunk lists a and b, while adjusting b for offset changes in a/
   this deletes a and b and returns the resultant list. */
static struct flist *combine(struct flist *a, struct flist *b)
{
	struct flist *c = NULL;
	struct frag *bh, *ct;
	int offset = 0, post;

	if (a && b)
		c = lalloc((lsize(a) + lsize(b)) * 2);

	if (c) {

		for (bh = b->head; bh != b->tail; bh++) {
			/* save old hunks */
			offset = gather(c, a, bh->start, offset);

			/* discard replaced hunks */
			post = discard(a, bh->end, offset);

			/* insert new hunk */
			ct = c->tail;
			ct->start = bh->start - offset;
			ct->end = bh->end - post;
			ct->len = bh->len;
			ct->data = bh->data;
			c->tail++;
			offset = post;
		}

		/* hold on to tail from a */
		memcpy(c->tail, a->head, sizeof(struct frag) * lsize(a));
		c->tail += lsize(a);
	}

	lfree(a);
	lfree(b);
	return c;
}

/* decode a binary patch into a hunk list */
static struct flist *decode(const char *bin, int len)
{
	struct flist *l;
	struct frag *lt;
	const char *data = bin + 12, *end = bin + len;
	char decode[12]; /* for dealing with alignment issues */

	/* assume worst case size, we won't have many of these lists */
	l = lalloc(len / 12);
	if (!l)
		return NULL;

	lt = l->tail;

	while (data <= end) {
		memcpy(decode, bin, 12);    
		lt->start = (uint32_t)ntohl(*(uint32_t *)decode);
		lt->end = (uint32_t)ntohl(*(uint32_t *)(decode + 4));
		lt->len = (uint32_t)ntohl(*(uint32_t *)(decode + 8));
		if (lt->start > lt->end)
			break; /* sanity check */
		bin = data + lt->len;
		if (bin < data)
			break; /* big data + big (bogus) len can wrap around */
		lt->data = data;
		data = bin + 12;
		lt++;
	}

	if (bin != end) {
        rb_raise(rb_eStandardError, "patch cannot be decoded");
		lfree(l);
		return NULL;
	}

	l->tail = lt;
	return l;
}

/* calculate the size of resultant text */
static int calcsize(int len, struct flist *l)
{
	int outlen = 0, last = 0;
	struct frag *f = l->head;

	while (f != l->tail) {
		if (f->start < last || f->end > len) {
			rb_raise(rb_eStandardError, "invalid patch");
			return -1;
		}
		outlen += f->start - last;
		last = f->end;
		outlen += f->len;
		f++;
	}

	outlen += len - last;
	return outlen;
}

static int apply(char *buf, const char *orig, int len, struct flist *l)
{
	struct frag *f = l->head;
	int last = 0;
	char *p = buf;

	while (f != l->tail) {
		if (f->start < last || f->end > len) {
		    rb_raise(rb_eStandardError, "invalid patch");
			return 0;
		}
		memcpy(p, orig + last, f->start - last);
		p += f->start - last;
		memcpy(p, f->data, f->len);
		last = f->end;
		p += f->len;
		f++;
	}
	memcpy(p, orig + last, len - last);
	return 1;
}

/* recursively generate a patch of all bins between start and end */
static struct flist *fold(VALUE bins, int start, int end)
{
	int len;
	int blen;
	const char *buffer;
    VALUE str;

	if (start + 1 == end) {
		/* trivial case, output a decoded list */
		VALUE tmp = rb_ary_entry(bins, start);
		if (!tmp)
			return NULL;
        str = rb_str_new3(tmp);
		if (!str || str == Qnil)
			return NULL;
        blen = RSTRING_LEN(str);
        buffer = RSTRING_PTR(str);
		return decode(buffer, blen);
	}

	/* divide and conquer, memory management is elsewhere */
	len = (end - start) / 2;
	return combine(fold(bins, start, start + len),
		       fold(bins, start + len, end));
}

static VALUE amp_mpatch_apply_patches(VALUE self, VALUE text, VALUE bins)
{
	VALUE result;
	struct flist *patch;
	const char *in;
	char *out;
	int len, outlen;
	int inlen;

	len = RARRAY_LEN(bins);
	if (!len) {
		/* nothing to do */
		return text;
	}
    
    in = RSTRING_PTR(text);
    inlen = RSTRING_LEN(text);

	patch = fold(bins, 0, len);
	if (!patch)
		return Qnil;

	outlen = calcsize(inlen, patch);
	if (outlen < 0) {
		result = Qnil;
		goto cleanup;
	}
    result = rb_str_new(NULL, outlen);
	if (!result) {
		result = Qnil;
		goto cleanup;
	}
	out = RSTRING_PTR(result);
	if (!apply(out, in, inlen, patch)) {
		result = Qnil;
	}
cleanup:
	lfree(patch);
	return result;
}

static VALUE amp_mpatch_patched_size(VALUE self, VALUE orig_r, VALUE bin_r)
{
	uint32_t orig, start, end, len, outlen = 0, last = 0;
	int patchlen;
	char *bin, *binend, *data;
	char decode[12]; /* for dealing with alignment issues */
    
    orig = FIX2INT(orig_r);
    bin = RSTRING_PTR(bin_r);
    patchlen = RSTRING_LEN(bin_r);
	
	binend = bin + patchlen;
	data = bin + 12;

	while (data <= binend) {
		memcpy(decode, bin, 12);
		start = (uint32_t)ntohl(*(uint32_t *)decode);
		end = (uint32_t)ntohl(*(uint32_t *)(decode + 4));
		len = (uint32_t)ntohl(*(uint32_t *)(decode + 8));
		if (start > end)
			break; /* sanity check */
		bin = data + len;
		if (bin < data)
			break; /* big data + big (bogus) len can wrap around */
		data = bin + 12;
		outlen += start - last;
		last = end;
		outlen += len;
	}

	if (bin != binend) {
        rb_raise(rb_eStandardError, "patch cannot be decoded");
		return Qnil;
	}

	outlen += orig - last;
    return INT2FIX(outlen);
}


void Init_MercurialPatch() {
    
    rb_mAmp = rb_define_module("Amp");
    rb_mDiffs = rb_define_module_under(rb_mAmp, "Diffs");
    rb_mMercurialPatch = rb_define_module_under(rb_mDiffs, "MercurialPatch");
    
    rb_define_singleton_method(rb_mMercurialPatch, "patched_size", amp_mpatch_patched_size, 2);
    rb_define_singleton_method(rb_mMercurialPatch, "apply_patches", amp_mpatch_apply_patches, 2);
}