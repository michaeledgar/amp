#include <ruby.h>
#ifdef RUBY_19
    #include <ruby/io.h>
#else
    #include <rubyio.h>
#endif

#include <bzlib.h>

static VALUE bz_cWriter, bz_cReader, bz_cInternal;
static VALUE bz_eError, bz_eConfigError, bz_eEOZError;

static VALUE bz_internal_ary;

static ID id_new, id_write, id_open, id_flush, id_read;
static ID id_closed, id_close, id_str;

#define BZ2_RB_CLOSE    1
#define BZ2_RB_INTERNAL 2

struct bz_file {
    bz_stream bzs;
    VALUE in, io;
    char *buf;
    int buflen;
    int blocks, work, small;
    int flags, lineno, state;
};

struct bz_str {
    VALUE str;
    int pos;
};

struct bz_iv {
    VALUE bz2, io;
    void (*finalize)();
};

#define Get_BZ2(obj, bzf)			\
    rb_io_taint_check(obj);			\
    Data_Get_Struct(obj, struct bz_file, bzf);	\
    if (!RTEST(bzf->io)) {			\
	rb_raise(rb_eIOError, "closed IO");	\
    }

static VALUE
bz_raise(error)
    int error;
{
    VALUE exc;
    char *msg;

    exc = bz_eError;
    switch (error) {
    case BZ_SEQUENCE_ERROR:
	msg = "uncorrect sequence"; 
	break;
    case BZ_PARAM_ERROR: 
	msg = "parameter out of range";
	break;
    case BZ_MEM_ERROR: 
	msg = "not enough memory is available"; 
	break;
    case BZ_DATA_ERROR:
	msg = "data integrity error is detected";
	break;
    case BZ_DATA_ERROR_MAGIC:
	msg = "compressed stream does not start with the correct magic bytes";
	break;
    case BZ_IO_ERROR: 
	msg = "error reading or writing"; 
	break;
    case BZ_UNEXPECTED_EOF: 
	exc = bz_eEOZError;
	msg = "compressed file finishes before the logical end of stream is detected";
	break;
    case BZ_OUTBUFF_FULL:
	msg = "output buffer full";
	break;
    case BZ_CONFIG_ERROR:
	exc = bz_eConfigError;
	msg = "library has been improperly compiled on your platform";
	break;
    default:
	msg = "unknown error";
	exc = bz_eError;
    }
    rb_raise(exc, "%s", msg);
}
    
static void
bz_str_mark(bzs)
    struct bz_str *bzs;
{
    rb_gc_mark(bzs->str);
}

static void
bz_file_mark(bzf)
    struct bz_file *bzf;
{
    rb_gc_mark(bzf->io);
    rb_gc_mark(bzf->in);
}

static struct bz_iv *
bz_find_struct(obj, ptr, posp)
    VALUE obj;
    void *ptr;
    int *posp;
{
    struct bz_iv *bziv;
    int i;
    
    for (i = 0; i < RARRAY_LEN(bz_internal_ary); i++) {
	    Data_Get_Struct(RARRAY_PTR(bz_internal_ary)[i], struct bz_iv, bziv);
	    if (ptr) {
	        if (TYPE(bziv->io) == T_FILE && RFILE(bziv->io)->fptr == ptr) { // ptr is OpenFile * or rb_io_t*
	    	    if (posp) 
	    	        *posp = i;
	    	    return bziv;
	        } else {
	            if (TYPE(bziv->io) == T_DATA && DATA_PTR(bziv->io) == ptr) {
	    	        if (posp) 
	    	            *posp = i;
	    	        return bziv;
	            }
	        }
	    } else if (bziv->io == obj) {
	        if (posp) 
	            *posp = i;
	        return bziv;
	    }
    }
    if (posp) *posp = -1;
    return 0;
}

static VALUE
bz_writer_internal_flush(bzf)
    struct bz_file *bzf;
{
    int closed = 1;

    if (rb_respond_to(bzf->io, id_closed)) {
	closed = RTEST(rb_funcall2(bzf->io, id_closed, 0, 0));
    }
    if (bzf->buf) {
	if (!closed && bzf->state == BZ_OK) {
	    bzf->bzs.next_in = NULL;
	    bzf->bzs.avail_in = 0;
	    do {
		bzf->bzs.next_out = bzf->buf;
		bzf->bzs.avail_out = bzf->buflen;
		bzf->state = BZ2_bzCompress(&(bzf->bzs), BZ_FINISH);
		if (bzf->state != BZ_FINISH_OK && 
		    bzf->state != BZ_STREAM_END) {
		    break;
		}
		if (bzf->bzs.avail_out < bzf->buflen) {
		    rb_funcall(bzf->io, id_write, 1,
			       rb_str_new(bzf->buf, 
					  bzf->buflen - bzf->bzs.avail_out));
		}
	    } while (bzf->state != BZ_STREAM_END);
	}
	free(bzf->buf);
	bzf->buf = 0;
	BZ2_bzCompressEnd(&(bzf->bzs));
	bzf->state = BZ_OK;
	if (!closed && rb_respond_to(bzf->io, id_flush)) {
	    rb_funcall2(bzf->io, id_flush, 0, 0);
	}
    }
    return closed;
}

static VALUE
bz_writer_internal_close(bzf)
    struct bz_file *bzf;
{
    struct bz_iv *bziv;
    int pos, closed;
    VALUE res;

    closed = bz_writer_internal_flush(bzf);
    bziv = bz_find_struct(bzf->io, 0, &pos);
    if (bziv) {
	if (TYPE(bzf->io) == T_FILE) {
	    RFILE(bzf->io)->fptr->finalize = bziv->finalize;
	}
	else if (TYPE(bziv->io) == T_DATA) {
	    RDATA(bziv->io)->dfree = bziv->finalize;
	}
	RDATA(bziv->bz2)->dfree = ruby_xfree;
	bziv->bz2 = 0;
	rb_ary_delete_at(bz_internal_ary, pos);
    }
    if (bzf->flags & BZ2_RB_CLOSE) {
	bzf->flags &= ~BZ2_RB_CLOSE;
	if (!closed && rb_respond_to(bzf->io, id_close)) {
	    rb_funcall2(bzf->io, id_close, 0, 0);
	}
	res = Qnil;
    }
    else {
	res = bzf->io;
    }
    bzf->io = Qnil;
    return res;
}

static VALUE
bz_internal_finalize(ary, obj)
    VALUE ary, obj;
{
    VALUE elem;
    int closed, i;
    struct bz_iv *bziv;
    struct bz_file *bzf;
    for (i = 0; i < RARRAY_LEN(ary); i++) {
	    elem = RARRAY_PTR(ary)[i];
	    Data_Get_Struct(elem, struct bz_iv, bziv);
	    if (bziv->bz2) {
	        RDATA(bziv->bz2)->dfree = ruby_xfree;
	        if (TYPE(bziv->io) == T_FILE) {
	    	    RFILE(bziv->io)->fptr->finalize = bziv->finalize;
	        }
	        else if (TYPE(bziv->io) == T_DATA) {
	    	    RDATA(bziv->io)->dfree = bziv->finalize;
	        }
	        Data_Get_Struct(bziv->bz2, struct bz_file, bzf);
	        closed = bz_writer_internal_flush(bzf);
	        if (bzf->flags & BZ2_RB_CLOSE) {
	    	    bzf->flags &= ~BZ2_RB_CLOSE;
	    	    if (!closed && rb_respond_to(bzf->io, id_close)) {
	    	        rb_funcall2(bzf->io, id_close, 0, 0);
	    	    }
	        }
	    }
    }
    return Qnil;
}

static VALUE
bz_writer_close(obj)
    VALUE obj;
{
    struct bz_file *bzf;
    VALUE res;

    Get_BZ2(obj, bzf);
    res = bz_writer_internal_close(bzf);
    if (!NIL_P(res) && (bzf->flags & BZ2_RB_INTERNAL)) {
	RBASIC(res)->klass = rb_cString;
    }
    return res;
}

static VALUE
bz_writer_close_bang(obj)
    VALUE obj;
{
    struct bz_file *bzf;
    int closed;

    Get_BZ2(obj, bzf);
    closed = bzf->flags & (BZ2_RB_INTERNAL|BZ2_RB_CLOSE);
    bz_writer_close(obj);
    if (!closed && rb_respond_to(bzf->io, id_close)) {
	if (rb_respond_to(bzf->io, id_closed)) {
	    closed = RTEST(rb_funcall2(bzf->io, id_closed, 0, 0));
	}
	if (!closed) {
	    rb_funcall2(bzf->io, id_close, 0, 0);
	}
    }
    return Qnil;
}

static void
bz_writer_free(bzf)
    struct bz_file *bzf;
{
    bz_writer_internal_close(bzf);
    ruby_xfree(bzf);
}

static void
bz_io_data_finalize(ptr)
    void *ptr;
{
    struct bz_file *bzf;
    struct bz_iv *bziv;
    int pos;

    bziv = bz_find_struct(0, ptr, &pos);
    if (bziv) {
	    rb_ary_delete_at(bz_internal_ary, pos);
	    Data_Get_Struct(bziv->bz2, struct bz_file, bzf);
	    rb_protect(bz_writer_internal_flush, (VALUE)bzf, 0);
	    RDATA(bziv->bz2)->dfree = ruby_xfree;
	    if (bziv->finalize) {
	        (*bziv->finalize)(ptr);
	    } else if (TYPE(bzf->io) == T_FILE) {
	        // close bzf->io. 
	        #ifdef RUBY_19
	            rb_io_close(bzf->io);
	        #else
	            OpenFile *file = (OpenFile *)ptr;
	            if (file->f) {
	    	        fclose(file->f);
	    	        file->f = 0;
	            }
	            if (file->f2) {
	    	        fclose(file->f2);
	    	        file->f2 = 0;
	            }
	        #endif
	    }
    }
}

static void *
bz_malloc(opaque, m, n)
    void *opaque;
    int m, n;
{
    return ruby_xmalloc(m * n);
}

static void
bz_free(opaque, p)
    void *opaque, *p;
{
    ruby_xfree(p);
}

#define DEFAULT_BLOCKS 9

static VALUE
bz_writer_s_alloc(obj)
    VALUE obj;
{
    struct bz_file *bzf;
    VALUE res;
    res = Data_Make_Struct(obj, struct bz_file, bz_file_mark, 
			   bz_writer_free, bzf);
    bzf->bzs.bzalloc = bz_malloc;
    bzf->bzs.bzfree = bz_free;
    bzf->blocks = DEFAULT_BLOCKS;
    bzf->state = BZ_OK;
    return res;
}

static VALUE
bz_writer_flush(obj)
    VALUE obj;
{
    struct bz_file *bzf;

    Get_BZ2(obj, bzf);
    if (bzf->flags & BZ2_RB_INTERNAL) {
	return bz_writer_close(obj);
    }
    bz_writer_internal_flush(bzf);
    return Qnil;
}

static VALUE
bz_writer_s_open(argc, argv, obj)
    int argc;
    VALUE obj, *argv;
{
    VALUE res;
    struct bz_file *bzf;

    if (argc < 1) {
	rb_raise(rb_eArgError, "invalid number of arguments");
    }
    if (argc == 1) {
	argv[0] = rb_funcall(rb_mKernel, id_open, 2, argv[0], 
			     rb_str_new2("wb"));
    }
    else {
	argv[1] = rb_funcall2(rb_mKernel, id_open, 2, argv);
	argv += 1;
	argc -= 1;
    }
    res = rb_funcall2(obj, id_new, argc, argv);
    Data_Get_Struct(res, struct bz_file, bzf);
    bzf->flags |= BZ2_RB_CLOSE;
    if (rb_block_given_p()) {
	return rb_ensure(rb_yield, res, bz_writer_close, res);
    }
    return res;
}

static VALUE
bz_str_write(obj, str)
    VALUE obj, str;
{
    if (TYPE(str) != T_STRING) {
	rb_raise(rb_eArgError, "expected a String");
    }
    if (RSTRING_LEN(str)) {
	rb_str_cat(obj, RSTRING_PTR(str), RSTRING_LEN(str));
    }
    return str;
}

static VALUE
bz_str_closed(obj)
    VALUE obj;
{
    return Qfalse;
}

static VALUE
bz_writer_init(argc, argv, obj)
    int argc;
    VALUE obj, *argv;
{
    struct bz_file *bzf;
    int blocks = DEFAULT_BLOCKS;
    int work = 0;
    VALUE a, b, c;

    switch(rb_scan_args(argc, argv, "03", &a, &b, &c)) {
    case 3:
	work = NUM2INT(c);
	/* ... */
    case 2:
	blocks = NUM2INT(b);
    }
    Data_Get_Struct(obj, struct bz_file, bzf);
    if (NIL_P(a)) {
	a = rb_str_new(0, 0);
	rb_define_method(rb_singleton_class(a), "write", bz_str_write, 1);
	rb_define_method(rb_singleton_class(a), "closed?", bz_str_closed, 0);
	bzf->flags |= BZ2_RB_INTERNAL;
    }
    else {
	VALUE iv;
	struct bz_iv *bziv;
	#ifdef RUBY_19
        rb_io_t *fptr;
    #else
	    OpenFile *fptr;
    #endif
	rb_io_taint_check(a);
	if (!rb_respond_to(a, id_write)) {
	    rb_raise(rb_eArgError, "first argument must respond to #write");
	}
	if (TYPE(a) == T_FILE) {
	    GetOpenFile(a, fptr);
	    rb_io_check_writable(fptr);
	}
	else if (rb_respond_to(a, id_closed)) {
	    iv = rb_funcall2(a, id_closed, 0, 0);
	    if (RTEST(iv)) {
		rb_raise(rb_eArgError, "closed object");
	    }
	}
	bziv = bz_find_struct(a, 0, 0);
	if (bziv) {
	    if (RTEST(bziv->bz2)) {
		rb_raise(rb_eArgError, "invalid data type");
	    }
	    bziv->bz2 = obj;
	}
	else {
	    iv = Data_Make_Struct(rb_cData, struct bz_iv, 0, free, bziv);
	    bziv->io = a;
	    bziv->bz2 = obj;
	    rb_ary_push(bz_internal_ary, iv);
	}
	switch (TYPE(a)) {
	case T_FILE:
	    bziv->finalize = RFILE(a)->fptr->finalize;
	    RFILE(a)->fptr->finalize = bz_io_data_finalize;
	    break;
	case T_DATA:
	    bziv->finalize = RDATA(a)->dfree;
	    RDATA(a)->dfree = bz_io_data_finalize;
	    break;
	}
    }
    bzf->io = a;
    bzf->blocks = blocks;
    bzf->work = work;
    return obj;
}

#define BZ_RB_BLOCKSIZE 4096

static VALUE
bz_writer_write(obj, a)
    VALUE obj, a;
{
    struct bz_file *bzf;
    int n;

    a = rb_obj_as_string(a);
    Get_BZ2(obj, bzf);
    if (!bzf->buf) {
	if (bzf->state != BZ_OK) {
	    bz_raise(bzf->state);
	}
	bzf->state = BZ2_bzCompressInit(&(bzf->bzs), bzf->blocks,
					0, bzf->work);
	if (bzf->state != BZ_OK) {
	    bz_writer_internal_flush(bzf);
	    bz_raise(bzf->state);
	}
	bzf->buf = ALLOC_N(char, BZ_RB_BLOCKSIZE + 1);
	bzf->buflen = BZ_RB_BLOCKSIZE;
	bzf->buf[0] = bzf->buf[bzf->buflen] = '\0';
    }
    bzf->bzs.next_in = RSTRING_PTR(a);
    bzf->bzs.avail_in = RSTRING_LEN(a);
    while (bzf->bzs.avail_in) {
	bzf->bzs.next_out = bzf->buf;
	bzf->bzs.avail_out = bzf->buflen;
	bzf->state = BZ2_bzCompress(&(bzf->bzs), BZ_RUN);
	if (bzf->state == BZ_SEQUENCE_ERROR || bzf->state == BZ_PARAM_ERROR) {
	    bz_writer_internal_flush(bzf);
	    bz_raise(bzf->state);
	}
	bzf->state = BZ_OK;
	if (bzf->bzs.avail_out < bzf->buflen) {
	    n = bzf->buflen - bzf->bzs.avail_out;
	    rb_funcall(bzf->io, id_write, 1, rb_str_new(bzf->buf, n));
	}
    }
    return INT2NUM(RSTRING_LEN(a));
}

static VALUE
bz_writer_putc(obj, a)
    VALUE obj, a;
{
    char c = NUM2CHR(a);
    return bz_writer_write(obj, rb_str_new(&c, 1));
}

static VALUE
bz_compress(argc, argv, obj)
    int argc;
    VALUE obj, *argv;
{
    VALUE bz2, str;

    if (!argc) {
	rb_raise(rb_eArgError, "need a String to compress");
    }
    str = rb_str_to_str(argv[0]);
    argv[0] = Qnil;
    bz2 = rb_funcall2(bz_cWriter, id_new, argc, argv);
    if (OBJ_TAINTED(str)) {
	struct bz_file *bzf;
	Data_Get_Struct(bz2, struct bz_file, bzf);
	OBJ_TAINT(bzf->io);
    }
    bz_writer_write(bz2, str);
    return bz_writer_close(bz2);
}

static VALUE
bz_reader_s_alloc(obj)
    VALUE obj;
{
    struct bz_file *bzf;
    VALUE res;
    res = Data_Make_Struct(obj, struct bz_file, bz_file_mark, 
			   ruby_xfree, bzf);
    bzf->bzs.bzalloc = bz_malloc;
    bzf->bzs.bzfree = bz_free;
    bzf->blocks = DEFAULT_BLOCKS;
    bzf->state = BZ_OK;
    return res;
}

static VALUE bz_reader_close __((VALUE));

static VALUE
bz_reader_s_open(argc, argv, obj)
    int argc;
    VALUE obj, *argv;
{
    VALUE res;
    struct bz_file *bzf;

    if (argc < 1) {
	rb_raise(rb_eArgError, "invalid number of arguments");
    }
    argv[0] = rb_funcall2(rb_mKernel, id_open, 1, argv);
    if (NIL_P(argv[0])) return Qnil;
    res = rb_funcall2(obj, id_new, argc, argv);
    Data_Get_Struct(res, struct bz_file, bzf);
    bzf->flags |= BZ2_RB_CLOSE;
    if (rb_block_given_p()) {
	return rb_ensure(rb_yield, res, bz_reader_close, res);
    }
    return res;
}

static VALUE
bz_reader_init(argc, argv, obj)
    int argc;
    VALUE obj, *argv;
{
    struct bz_file *bzf;
    int small = 0;
    VALUE a, b;
    int internal = 0;

    if (rb_scan_args(argc, argv, "11", &a, &b) == 2) {
	    small = RTEST(b);
    }
    rb_io_taint_check(a);
    if (OBJ_TAINTED(a)) {
	    OBJ_TAINT(obj);
    }
    if (rb_respond_to(a, id_read)) {
	    if (TYPE(a) == T_FILE) {
	        #ifdef RUBY_19
                rb_io_t *fptr;
            #else
	            OpenFile *fptr;
	        #endif
	        GetOpenFile(a, fptr);
	        rb_io_check_readable(fptr);
	    } else if (rb_respond_to(a, id_closed)) {
	        VALUE iv = rb_funcall2(a, id_closed, 0, 0);
	        if (RTEST(iv)) {
	    	    rb_raise(rb_eArgError, "closed object");
	        }
	    }
    } else {
	    struct bz_str *bzs;
	    VALUE res;
        
	    if (!rb_respond_to(a, id_str)) {
	        rb_raise(rb_eArgError, "first argument must respond to #read");
	    }
	    a = rb_funcall2(a, id_str, 0, 0);
	    if (TYPE(a) != T_STRING) {
	        rb_raise(rb_eArgError, "#to_str must return a String");
	    }
	    res = Data_Make_Struct(bz_cInternal, struct bz_str, bz_str_mark, ruby_xfree, bzs);
	    bzs->str = a;
	    a = res;
	    internal = BZ2_RB_INTERNAL;
    }
    Data_Get_Struct(obj, struct bz_file, bzf);
    bzf->io = a;
    bzf->small = small;
    bzf->flags |= internal;
    return obj;
}

static struct bz_file *
bz_get_bzf(obj)
    VALUE obj;
{
    struct bz_file *bzf;

    Get_BZ2(obj, bzf);
    if (!bzf->buf) {
	if (bzf->state != BZ_OK) {
	    bz_raise(bzf->state);
	}
	bzf->state = BZ2_bzDecompressInit(&(bzf->bzs), 0, bzf->small);
	if (bzf->state != BZ_OK) {
	    BZ2_bzDecompressEnd(&(bzf->bzs));
	    bz_raise(bzf->state);
	}
	bzf->buf = ALLOC_N(char, BZ_RB_BLOCKSIZE + 1);
	bzf->buflen = BZ_RB_BLOCKSIZE;
	bzf->buf[0] = bzf->buf[bzf->buflen] = '\0';
	bzf->bzs.total_out_hi32 = bzf->bzs.total_out_lo32 = 0;
	bzf->bzs.next_out = bzf->buf;
	bzf->bzs.avail_out = 0;
    }
    if (bzf->state == BZ_STREAM_END && !bzf->bzs.avail_out) {
	return 0;
    }
    return bzf;
}

static int
bz_next_available(bzf, in)
    struct bz_file *bzf;
    int in;
{
    bzf->bzs.next_out = bzf->buf;
    bzf->bzs.avail_out = 0;
    if (bzf->state == BZ_STREAM_END) {
	return BZ_STREAM_END;
    }
    if (!bzf->bzs.avail_in) {
	bzf->in = rb_funcall(bzf->io, id_read, 1, INT2FIX(1024));
	if (TYPE(bzf->in) != T_STRING || RSTRING_LEN(bzf->in) == 0) {
	    BZ2_bzDecompressEnd(&(bzf->bzs));
	    bzf->bzs.avail_out = 0;
	    bzf->state = BZ_UNEXPECTED_EOF;
	    bz_raise(bzf->state);
	}
	bzf->bzs.next_in = RSTRING_PTR(bzf->in);
	bzf->bzs.avail_in = RSTRING_LEN(bzf->in);
    }
    if ((bzf->buflen - in) < (BZ_RB_BLOCKSIZE / 2)) {
	bzf->buf = REALLOC_N(bzf->buf, char, bzf->buflen+BZ_RB_BLOCKSIZE+1);
	bzf->buflen += BZ_RB_BLOCKSIZE;
	bzf->buf[bzf->buflen] = '\0';
    }
    bzf->bzs.avail_out = bzf->buflen - in;
    bzf->bzs.next_out = bzf->buf + in;
    bzf->state = BZ2_bzDecompress(&(bzf->bzs));
    if (bzf->state != BZ_OK) {
	BZ2_bzDecompressEnd(&(bzf->bzs));
	if (bzf->state != BZ_STREAM_END) {
	    bzf->bzs.avail_out = 0;
	    bz_raise(bzf->state);
	}
    }
    bzf->bzs.avail_out = bzf->buflen - bzf->bzs.avail_out;
    bzf->bzs.next_out = bzf->buf;
    return 0;
}

#define ASIZE (1 << CHAR_BIT)

static VALUE
bz_read_until(bzf, str, len, td1)
    struct bz_file *bzf;
    char *str;
    int len;
    int *td1;
{
    VALUE res;
    int total, i, nex = 0;
    char *p, *t, *tx, *end, *pend = str + len;

    res = rb_str_new(0, 0);
    while (1) {
	total = bzf->bzs.avail_out;
	if (len == 1) {
	    tx = memchr(bzf->bzs.next_out, *str, bzf->bzs.avail_out);
	    if (tx) {
		i = tx - bzf->bzs.next_out + len;
		res = rb_str_cat(res, bzf->bzs.next_out, i);
		bzf->bzs.next_out += i;
		bzf->bzs.avail_out -= i;
		return res;
	    }
	}
	else {
	    tx = bzf->bzs.next_out;
	    end = bzf->bzs.next_out + bzf->bzs.avail_out;
	    while (tx + len <= end) {
		for (p = str, t = tx; p != pend; ++p, ++t) {
		    if (*p != *t) break;
		}
		if (p == pend) {
		    i = tx - bzf->bzs.next_out + len;
		    res = rb_str_cat(res, bzf->bzs.next_out, i);
		    bzf->bzs.next_out += i;
		    bzf->bzs.avail_out -= i;
		    return res;
		}
		if (td1) {
		    tx += td1[(int)*(tx + len)];
		}
		else {
		    tx += 1;
		}
	    }
	}
	nex = 0;
	if (total) {
	    nex = len - 1;
	    res = rb_str_cat(res, bzf->bzs.next_out, total - nex);
	    if (nex) {
		MEMMOVE(bzf->buf, bzf->bzs.next_out + total - nex, char, nex);
	    }
	}
	if (bz_next_available(bzf, nex) == BZ_STREAM_END) {
	    if (nex) {
		res = rb_str_cat(res, bzf->buf, nex);
	    }
	    if (RSTRING_LEN(res)) {
		return res;
	    }
	    return Qnil;
	}
    }
    return Qnil;
}

static int
bz_read_while(bzf, c)
    struct bz_file *bzf;
    char c;
{
    char *end;

    while (1) {
	end = bzf->bzs.next_out + bzf->bzs.avail_out;
	while (bzf->bzs.next_out < end) {
	    if (c != *bzf->bzs.next_out) {
		bzf->bzs.avail_out = end -  bzf->bzs.next_out;
		return *bzf->bzs.next_out;
	    }
	    ++bzf->bzs.next_out;
	}
	if (bz_next_available(bzf, 0) == BZ_STREAM_END) {
	    return EOF;
	}
    }
    return EOF;
}

static VALUE
bz_reader_read(argc, argv, obj)
    int argc;
    VALUE obj, *argv;
{
    struct bz_file *bzf;
    VALUE res, length;
    int total;
    int n;

    rb_scan_args(argc, argv, "01", &length);
    if (NIL_P(length)) {
	n = -1;
    }
    else {
	n = NUM2INT(length);
	if (n < 0) {
	    rb_raise(rb_eArgError, "negative length %d given", n);
	}
    }
    bzf = bz_get_bzf(obj);
    if (!bzf) {
	return Qnil;
    }
    res = rb_str_new(0, 0);
    if (OBJ_TAINTED(obj)) {
	OBJ_TAINT(res);
    }
    if (n == 0) {
	return res;
    }
    while (1) {
	total = bzf->bzs.avail_out;
	if (n != -1 && (RSTRING_LEN(res) + total) >= n) {
	    n -= RSTRING_LEN(res);
	    res = rb_str_cat(res, bzf->bzs.next_out, n);
	    bzf->bzs.next_out += n;
	    bzf->bzs.avail_out -= n;
	    return res;
	}
	if (total) {
	    res = rb_str_cat(res, bzf->bzs.next_out, total);
	}
	if (bz_next_available(bzf, 0) == BZ_STREAM_END) {
	    return res;
	}
    }
    return Qnil;
}

static int
bz_getc(obj)
    VALUE obj;
{
    VALUE length = INT2FIX(1);
    VALUE res = bz_reader_read(1, &length, obj);
    if (NIL_P(res) || RSTRING_LEN(res) == 0) {
	return EOF;
    }
    return RSTRING_PTR(res)[0];
}

static VALUE
bz_reader_ungetc(obj, a)
    VALUE obj, a;
{
    struct bz_file *bzf;
    int c = NUM2INT(a);

    Get_BZ2(obj, bzf);
    if (!bzf->buf) {
	bz_raise(BZ_SEQUENCE_ERROR);
    }
    if (bzf->bzs.avail_out < bzf->buflen) {
	bzf->bzs.next_out -= 1;
	bzf->bzs.next_out[0] = c;
	bzf->bzs.avail_out += 1;
    }
    else {
	bzf->buf = REALLOC_N(bzf->buf, char, bzf->buflen + 2);
	bzf->buf[bzf->buflen++] = c;
	bzf->buf[bzf->buflen] = '\0';
	bzf->bzs.next_out = bzf->buf;
	bzf->bzs.avail_out = bzf->buflen;
    }
    return Qnil;
}

static VALUE
bz_reader_ungets(obj, a)
    VALUE obj, a;
{
    struct bz_file *bzf;

    Check_Type(a, T_STRING);
    Get_BZ2(obj, bzf);
    if (!bzf->buf) {
	bz_raise(BZ_SEQUENCE_ERROR);
    }
    if ((bzf->bzs.avail_out + RSTRING_LEN(a)) < bzf->buflen) {
	bzf->bzs.next_out -= RSTRING_LEN(a);
	MEMCPY(bzf->bzs.next_out, RSTRING_PTR(a), char, RSTRING_LEN(a));
	bzf->bzs.avail_out += RSTRING_LEN(a);
    }
    else {
	bzf->buf = REALLOC_N(bzf->buf, char, bzf->buflen + RSTRING_LEN(a) + 1);
	MEMCPY(bzf->buf + bzf->buflen, RSTRING_PTR(a), char,RSTRING_LEN(a));
	bzf->buflen += RSTRING_LEN(a);
	bzf->buf[bzf->buflen] = '\0';
	bzf->bzs.next_out = bzf->buf;
	bzf->bzs.avail_out = bzf->buflen;
    }
    return Qnil;
}

VALUE
bz_reader_gets(obj)
    VALUE obj;
{
    struct bz_file *bzf;
    VALUE str = Qnil;

    bzf = bz_get_bzf(obj);
    if (bzf) {
	str = bz_read_until(bzf, "\n", 1, 0);
	if (!NIL_P(str)) {
	    bzf->lineno++;
	    OBJ_TAINT(str);
	}
    }
    return str;
}

static VALUE
bz_reader_gets_internal(argc, argv, obj, td, init)
    int argc;
    VALUE obj, *argv;
    int *td, init;
{
    struct bz_file *bzf;
    VALUE rs, res;
    char *rsptr;
    int rslen, rspara, *td1;

    rs = rb_rs;
    if (argc) {
	rb_scan_args(argc, argv, "1", &rs);
	if (!NIL_P(rs)) {
	    Check_Type(rs, T_STRING);
	}
    }
    if (NIL_P(rs)) {
	return bz_reader_read(1, &rs, obj);
    }
    rslen = RSTRING_LEN(rs);
    if (rs == rb_default_rs || (rslen == 1 && RSTRING_PTR(rs)[0] == '\n')) {
	return bz_reader_gets(obj);
    }

    if (rslen == 0) {
	rsptr = "\n\n";
	rslen = 2;
	rspara = 1;
    }
    else {
	rsptr = RSTRING_PTR(rs);
	rspara = 0;
    }

    bzf = bz_get_bzf(obj);
    if (!bzf) {
	return Qnil;
    }
    if (rspara) {
	bz_read_while(bzf, '\n');
    }
    td1 = 0;
    if (rslen != 1) {
	if (init) {
	    int i;

	    for (i = 0; i < ASIZE; i++) {
		td[i] = rslen + 1;
	    }
	    for (i = 0; i < rslen; i++) {
		td[(int)*(rsptr + i)] = rslen - i;
	    }
	}
	td1 = td;
    }

    res = bz_read_until(bzf, rsptr, rslen, td1);
    if (rspara) {
	bz_read_while(bzf, '\n');
    }

    if (!NIL_P(res)) {
	bzf->lineno++;
	OBJ_TAINT(res);
    }
    return res;
}

static VALUE
bz_reader_set_unused(obj, a)
    VALUE obj, a;
{
    struct bz_file *bzf;

    Check_Type(a, T_STRING);
    Get_BZ2(obj, bzf);
    if (!bzf->in) {
	bzf->in = rb_str_new(RSTRING_PTR(a), RSTRING_LEN(a));
    }
    else {
	bzf->in = rb_str_cat(bzf->in, RSTRING_PTR(a), RSTRING_LEN(a));
    }
    bzf->bzs.next_in = RSTRING_PTR(bzf->in);
    bzf->bzs.avail_in = RSTRING_LEN(bzf->in);
    return Qnil;
}

static VALUE
bz_reader_getc(obj)
    VALUE obj;
{
    VALUE str;
    VALUE len = INT2FIX(1);

    str = bz_reader_read(1, &len, obj);
    if (NIL_P(str) || RSTRING_LEN(str) == 0) {
	return Qnil;
    }
    return INT2FIX(RSTRING_PTR(str)[0] & 0xff);
}

static void
bz_eoz_error()
{
    rb_raise(bz_eEOZError, "End of Zip component reached");
}

static VALUE
bz_reader_readchar(obj)
    VALUE obj;
{
    VALUE res = bz_reader_getc(obj);

    if (NIL_P(res)) {
	bz_eoz_error();
    }
    return res;
}

static VALUE
bz_reader_gets_m(argc, argv, obj)
    int argc;
    VALUE obj, *argv;
{
    int td[ASIZE];
    VALUE str = bz_reader_gets_internal(argc, argv, obj, td, Qtrue);

    if (!NIL_P(str)) {
	rb_lastline_set(str);
    }
    return str;
}

static VALUE
bz_reader_readline(argc, argv, obj)
    int argc;
    VALUE obj, *argv;
{
    VALUE res = bz_reader_gets_m(argc, argv, obj);

    if (NIL_P(res)) {
	bz_eoz_error();
    }
    return res;
}

static VALUE
bz_reader_readlines(argc, argv, obj)
    int argc;
    VALUE obj, *argv;
{
    VALUE line, ary;
    int td[ASIZE], in;

    in = Qtrue;
    ary = rb_ary_new();
    while (!NIL_P(line = bz_reader_gets_internal(argc, argv, obj, td, in))) {
	in = Qfalse;
	rb_ary_push(ary, line);
    }
    return ary;
}

static VALUE
bz_reader_each_line(argc, argv, obj)
    int argc;
    VALUE obj, *argv;
{
    VALUE line;
    int td[ASIZE], in;

    in = Qtrue;
    while (!NIL_P(line = bz_reader_gets_internal(argc, argv, obj, td, in))) {
	in = Qfalse;
	rb_yield(line);
    }
    return obj;
}

static VALUE
bz_reader_each_byte(obj)
    VALUE obj;
{
    int c;

    while ((c = bz_getc(obj)) != EOF) {
	rb_yield(INT2FIX(c & 0xff));
    }
    return obj;
}

static VALUE
bz_reader_unused(obj)
    VALUE obj;
{
    struct bz_file *bzf;
    VALUE res;

    Get_BZ2(obj, bzf);
    if (!bzf->in || bzf->state != BZ_STREAM_END) {
	return Qnil;
    }
    if (bzf->bzs.avail_in) {
	res = rb_tainted_str_new(bzf->bzs.next_in, bzf->bzs.avail_in);
	bzf->bzs.avail_in = 0;
    }
    else {
	res = rb_tainted_str_new(0, 0);
    }
    return res;
}

static VALUE
bz_reader_eoz(obj)
    VALUE obj;
{
    struct bz_file *bzf;

    Get_BZ2(obj, bzf);
    if (!bzf->in || !bzf->buf) {
	return Qnil;
    }
    if (bzf->state == BZ_STREAM_END && !bzf->bzs.avail_out) {
	return Qtrue;
    }
    return Qfalse;
}

static VALUE
bz_reader_eof(obj)
    VALUE obj;
{
    struct bz_file *bzf;
    VALUE res;

    res = bz_reader_eoz(obj);
    if (RTEST(res)) {
	Get_BZ2(obj, bzf);
	if (bzf->bzs.avail_in) {
	    res = Qfalse;
	}
	else {
	    res = bz_reader_getc(obj);
	    if (NIL_P(res)) {
		res = Qtrue;
	    }
	    else {
		bz_reader_ungetc(res);
		res = Qfalse;
	    }
	}
    }
    return res;
}

static VALUE
bz_reader_closed(obj)
    VALUE obj;
{
    struct bz_file *bzf;

    Data_Get_Struct(obj, struct bz_file, bzf);
    return RTEST(bzf->io)?Qfalse:Qtrue;
}

static VALUE
bz_reader_close(obj)
    VALUE obj;
{
    struct bz_file *bzf;
    VALUE res;

    Get_BZ2(obj, bzf);
    if (bzf->buf) {
	free(bzf->buf);
	bzf->buf = 0;
    }
    if (bzf->state == BZ_OK) {
	BZ2_bzDecompressEnd(&(bzf->bzs));
    }
    if (bzf->flags & BZ2_RB_CLOSE) {
	int closed = 0;
	if (rb_respond_to(bzf->io, id_closed)) {
	    VALUE iv = rb_funcall2(bzf->io, id_closed, 0, 0);
	    closed = RTEST(iv);
	}
	if (!closed && rb_respond_to(bzf->io, id_close)) {
	    rb_funcall2(bzf->io, id_close, 0, 0);
	}
    }
    if (bzf->flags & (BZ2_RB_CLOSE|BZ2_RB_INTERNAL)) {
	res = Qnil;
    }
    else {
	res = bzf->io;
    }
    bzf->io = 0;
    return res;
}

static VALUE
bz_reader_finish(obj)
    VALUE obj;
{
    struct bz_file *bzf;

    Get_BZ2(obj, bzf);
    if (bzf->buf) {
	rb_funcall2(obj, id_read, 0, 0);
	free(bzf->buf);
    }
    bzf->buf = 0;
    bzf->state = BZ_OK;
    return Qnil;
}

static VALUE
bz_reader_close_bang(obj)
    VALUE obj;
{
    struct bz_file *bzf;
    int closed;

    Get_BZ2(obj, bzf);
    closed = bzf->flags & (BZ2_RB_CLOSE|BZ2_RB_INTERNAL);
    bz_reader_close(obj);
    if (!closed && rb_respond_to(bzf->io, id_close)) {
	if (rb_respond_to(bzf->io, id_closed)) {
	    closed = RTEST(rb_funcall2(bzf->io, id_closed, 0, 0));
	}
	if (!closed) {
	    rb_funcall2(bzf->io, id_close, 0, 0);
	}
    }
    return Qnil;
}

struct foreach_arg {
    int argc;
    VALUE sep;
    VALUE obj;
};

static VALUE
bz_reader_foreach_line(arg)
    struct foreach_arg *arg;
{
    VALUE str;
    int td[ASIZE], in;

    in = Qtrue;
    while (!NIL_P(str = bz_reader_gets_internal(arg->argc, &arg->sep,
						arg->obj, td, in))) {
	in = Qfalse;
	rb_yield(str);
    }
    return Qnil;
}

static VALUE
bz_reader_s_foreach(argc, argv, obj)
    int argc;
    VALUE obj, *argv;
{
    VALUE fname, sep;
    struct foreach_arg arg;
    struct bz_file *bzf;

    if (!rb_block_given_p()) {
	rb_raise(rb_eArgError, "call out of a block");
    }
    rb_scan_args(argc, argv, "11", &fname, &sep);
    Check_SafeStr(fname);
    arg.argc = argc - 1;
    arg.sep = sep;
    arg.obj = rb_funcall2(rb_mKernel, id_open, 1, &fname);
    if (NIL_P(arg.obj)) return Qnil;
    arg.obj = rb_funcall2(obj, id_new, 1, &arg.obj);
    Data_Get_Struct(arg.obj, struct bz_file, bzf);
    bzf->flags |= BZ2_RB_CLOSE;
    return rb_ensure(bz_reader_foreach_line, (VALUE)&arg, bz_reader_close, arg.obj);
}

static VALUE
bz_reader_i_readlines(arg)
    struct foreach_arg *arg;
{
    VALUE str, res;
    int td[ASIZE], in;

    in = Qtrue;
    res = rb_ary_new();
    while (!NIL_P(str = bz_reader_gets_internal(arg->argc, &arg->sep,
						arg->obj, td, in))) {
	in = Qfalse;
	rb_ary_push(res, str);
    }
    return res;
}

static VALUE
bz_reader_s_readlines(argc, argv, obj)
    int argc;
    VALUE obj, *argv;
{
    VALUE fname, sep;
    struct foreach_arg arg;
    struct bz_file *bzf;

    rb_scan_args(argc, argv, "11", &fname, &sep);
    Check_SafeStr(fname);
    arg.argc = argc - 1;
    arg.sep = sep;
    arg.obj = rb_funcall2(rb_mKernel, id_open, 1, &fname);
    if (NIL_P(arg.obj)) return Qnil;
    arg.obj = rb_funcall2(obj, id_new, 1, &arg.obj);
    Data_Get_Struct(arg.obj, struct bz_file, bzf);
    bzf->flags |= BZ2_RB_CLOSE;
    return rb_ensure(bz_reader_i_readlines, (VALUE)&arg, bz_reader_close, arg.obj);
}

static VALUE
bz_reader_lineno(obj)
    VALUE obj;
{
    struct bz_file *bzf;

    Get_BZ2(obj, bzf);
    return INT2NUM(bzf->lineno);
}

static VALUE
bz_reader_set_lineno(obj, lineno)
    VALUE obj, lineno;
{
    struct bz_file *bzf;

    Get_BZ2(obj, bzf);
    bzf->lineno = NUM2INT(lineno);
    return lineno;
}

static VALUE
bz_to_io(obj)
    VALUE obj;
{
    struct bz_file *bzf;

    Get_BZ2(obj, bzf);
    return bzf->io;
}

static VALUE
bz_str_read(argc, argv, obj)
    int argc;
    VALUE obj, *argv;
{
    struct bz_str *bzs;
    VALUE res, len;
    int count;
    
    Data_Get_Struct(obj, struct bz_str, bzs);
    rb_scan_args(argc, argv, "01", &len);
    if (NIL_P(len)) {
	count = RSTRING_LEN(bzs->str);
    }
    else {
	count = NUM2INT(len);
	if (count < 0) {
	    rb_raise(rb_eArgError, "negative length %d given", count);
	}
    }
    if (!count || bzs->pos == -1) {
	return Qnil;
    }
    if ((bzs->pos + count) >= RSTRING_LEN(bzs->str)) {
	res = rb_str_new(RSTRING_PTR(bzs->str) + bzs->pos, 
			 RSTRING_LEN(bzs->str) - bzs->pos);
	bzs->pos = -1;
    }
    else {
	res = rb_str_new(RSTRING_PTR(bzs->str) + bzs->pos, count);
	bzs->pos += count;
    }
    return res;
}

static VALUE
bz_uncompress(argc, argv, obj)
    int argc;
    VALUE obj, *argv;
{
    VALUE bz2, nilv = Qnil;

    if (!argc) {
	rb_raise(rb_eArgError, "need a String to Uncompress");
    }
    argv[0] = rb_str_to_str(argv[0]);
    bz2 = rb_funcall2(bz_cReader, id_new, argc, argv);
    return bz_reader_read(1, &nilv, bz2);
}

static VALUE
bz_s_new(argc, argv, obj)
    int argc;
    VALUE obj, *argv;
{
    VALUE res = rb_funcall2(obj, rb_intern("allocate"), 0, 0);
    rb_obj_call_init(res, argc, argv);
    return res;
}

static VALUE
bz_proc_new(func, val)
    VALUE (*func)(ANYARGS);
    VALUE val;
{
    VALUE tmp = Data_Wrap_Struct(rb_cData, 0, 0, 0);
    rb_define_singleton_method(tmp, "tmp_proc", func, 1);
    return rb_funcall2(rb_funcall(tmp, rb_intern("method"), 1, 
                                  ID2SYM(rb_intern("tmp_proc"))),
                       rb_intern("to_proc"), 0, 0);
}

void Init_bz2()
{
    VALUE bz_mBZ2;

    if (rb_const_defined_at(rb_cObject, rb_intern("BZ2"))) {
	rb_raise(rb_eNameError, "module already defined");
    }

    bz_internal_ary = rb_ary_new();
    rb_global_variable(&bz_internal_ary);
    rb_funcall(rb_const_get(rb_cObject, rb_intern("ObjectSpace")), 
	       rb_intern("define_finalizer"), 2, bz_internal_ary,
	       bz_proc_new(bz_internal_finalize, 0));

    id_new    = rb_intern("new");
    id_write  = rb_intern("write");
    id_open   = rb_intern("open");
    id_flush  = rb_intern("flush");
    id_read   = rb_intern("read");
    id_close  = rb_intern("close");
    id_str    = rb_intern("to_str");
    id_closed = rb_intern("closed?");

    bz_mBZ2 = rb_define_module("BZ2");
    bz_eConfigError = rb_define_class_under(bz_mBZ2, "ConfigError", rb_eFatal);
    bz_eError = rb_define_class_under(bz_mBZ2, "Error", rb_eIOError);
    bz_eEOZError = rb_define_class_under(bz_mBZ2, "EOZError", bz_eError);

    rb_define_module_function(bz_mBZ2, "compress", bz_compress, -1);
    rb_define_module_function(bz_mBZ2, "uncompress", bz_uncompress, -1);
    rb_define_module_function(bz_mBZ2, "decompress", bz_uncompress, -1);
    rb_define_module_function(bz_mBZ2, "bzip2", bz_compress, -1);
    rb_define_module_function(bz_mBZ2, "bunzip2", bz_uncompress, -1);
    /*
      Writer
    */
    bz_cWriter = rb_define_class_under(bz_mBZ2, "Writer", rb_cData);
#if HAVE_RB_DEFINE_ALLOC_FUNC
    rb_define_alloc_func(bz_cWriter, bz_writer_s_alloc);
#else
    rb_define_singleton_method(bz_cWriter, "allocate", bz_writer_s_alloc, 0);
#endif    
    rb_define_singleton_method(bz_cWriter, "new", bz_s_new, -1);
    rb_define_singleton_method(bz_cWriter, "open", bz_writer_s_open, -1);
    rb_define_method(bz_cWriter, "initialize", bz_writer_init, -1);
    rb_define_method(bz_cWriter, "write", bz_writer_write, 1);
    rb_define_method(bz_cWriter, "putc", bz_writer_putc, 1);
    rb_define_method(bz_cWriter, "puts", rb_io_puts, -1);
    rb_define_method(bz_cWriter, "print", rb_io_print, -1);
    rb_define_method(bz_cWriter, "printf", rb_io_printf, -1);
    rb_define_method(bz_cWriter, "<<", rb_io_addstr, 1);
    rb_define_method(bz_cWriter, "flush", bz_writer_flush, 0);
    rb_define_method(bz_cWriter, "finish", bz_writer_flush, 0);
    rb_define_method(bz_cWriter, "close", bz_writer_close, 0);
    rb_define_method(bz_cWriter, "close!", bz_writer_close_bang, 0);
    rb_define_method(bz_cWriter, "to_io", bz_to_io, 0);
    /*
      Reader
    */
    bz_cReader = rb_define_class_under(bz_mBZ2, "Reader", rb_cData);
    rb_include_module(bz_cReader, rb_mEnumerable);
#if HAVE_RB_DEFINE_ALLOC_FUNC
    rb_define_alloc_func(bz_cReader, bz_reader_s_alloc);
#else
    rb_define_singleton_method(bz_cReader, "allocate", bz_reader_s_alloc, 0);
#endif
    rb_define_singleton_method(bz_cReader, "new", bz_s_new, -1);
    rb_define_singleton_method(bz_cReader, "open", bz_reader_s_open, -1);
    rb_define_singleton_method(bz_cReader, "foreach", bz_reader_s_foreach, -1);
    rb_define_singleton_method(bz_cReader, "readlines", bz_reader_s_readlines, -1);
    rb_define_method(bz_cReader, "initialize", bz_reader_init, -1);
    rb_define_method(bz_cReader, "read", bz_reader_read, -1);
    rb_define_method(bz_cReader, "unused", bz_reader_unused, 0);
    rb_define_method(bz_cReader, "unused=", bz_reader_set_unused, 1);
    rb_define_method(bz_cReader, "ungetc", bz_reader_ungetc, 1);
    rb_define_method(bz_cReader, "ungets", bz_reader_ungets, 1);
    rb_define_method(bz_cReader, "getc", bz_reader_getc, 0);
    rb_define_method(bz_cReader, "gets", bz_reader_gets_m, -1);
    rb_define_method(bz_cReader, "readchar", bz_reader_readchar, 0);
    rb_define_method(bz_cReader, "readline", bz_reader_readline, -1);
    rb_define_method(bz_cReader, "readlines", bz_reader_readlines, -1);
    rb_define_method(bz_cReader, "each", bz_reader_each_line, -1);
    rb_define_method(bz_cReader, "each_line", bz_reader_each_line, -1);
    rb_define_method(bz_cReader, "each_byte", bz_reader_each_byte, 0);
    rb_define_method(bz_cReader, "close", bz_reader_close, 0);
    rb_define_method(bz_cReader, "close!", bz_reader_close_bang, 0);
    rb_define_method(bz_cReader, "finish", bz_reader_finish, 0);
    rb_define_method(bz_cReader, "closed", bz_reader_closed, 0);
    rb_define_method(bz_cReader, "closed?", bz_reader_closed, 0);
    rb_define_method(bz_cReader, "eoz?", bz_reader_eoz, 0);
    rb_define_method(bz_cReader, "eoz", bz_reader_eoz, 0);
    rb_define_method(bz_cReader, "eof?", bz_reader_eof, 0);
    rb_define_method(bz_cReader, "eof", bz_reader_eof, 0);
    rb_define_method(bz_cReader, "lineno", bz_reader_lineno, 0);
    rb_define_method(bz_cReader, "lineno=", bz_reader_set_lineno, 1);
    rb_define_method(bz_cReader, "to_io", bz_to_io, 0);
    /*
      Internal
    */
    bz_cInternal = rb_define_class_under(bz_mBZ2, "InternalStr", rb_cData);
#if HAVE_RB_DEFINE_ALLOC_FUNC
    rb_undef_alloc_func(bz_cInternal);
#else
    rb_undef_method(CLASS_OF(bz_cInternal), "allocate");
#endif
    rb_undef_method(CLASS_OF(bz_cInternal), "new");
    rb_undef_method(bz_cInternal, "initialize");
    rb_define_method(bz_cInternal, "read", bz_str_read, -1);
}
