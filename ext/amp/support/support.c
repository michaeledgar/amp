#include <stdio.h>
#include <stdlib.h>
#include "ruby.h"

static int little_endian = -1;

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

/**
 * Byte-swaps a 64-bit fixnum.
 * Bignum arithmetic is quite, quite slow. By implementing this in C, we save ourselves
 * innumerable cycles. Also, our result will usually end up being a bignum, even though we
 * start as a fixnum.
 * 
 * @param self [in] the bignum that needs byte swapping
 * @return the byte-swapped number (or not swapped if host is big-endian)
 */
static VALUE amp_fixnum_byte_swap_64(VALUE self) {
    VALUE result = self;
    if (little_endian) {
    uint64_t val = (uint64_t)FIX2ULONG(self);
    val = (((val >> 56)) | ((val & 0x00FF000000000000ll) >> 40) |
         ((val & 0x0000FF0000000000ll) >> 24) | ((val & 0x000000FF00000000ll) >> 8)  |
         ((val & 0x00000000FF000000ll) << 8 ) | ((val & 0x0000000000FF0000ll) << 24) |
         ((val & 0x000000000000FF00ll) << 40) | ((val & 0x00000000000000FFll) << 56));
     result = rb_ull2inum(val);
    }
    return result;
}

/**
 * Converts an unsigned, 16-bit fixnum to a signed, 16-bit value.
 * Converts an unsigned, 16-bit number to its signed equivalent.
 * Since Ruby doesn't have signed values readily available, this is much 
 * much faster in C.
 *
 * @param self [in] the 16-bit unsigned short to make signed
 * @return the 16-bit signed equivalent
 */
static VALUE amp_fixnum_to_signed_16(VALUE self) {
    signed short val = (int16_t)FIX2INT(self);
    VALUE result = rb_int_new(val);
    return result;
}

/**
 * Converts a fixnum to a signed, 32-bit value.
 * Converts an unsigned, 32-bit number to its signed equivalent. Since Ruby
 * doesn't have signed values readily available, this is much much faster in
 * C. This will only be called if the number being converted is smaller than
 * the fixnum max.
 *
 * @param self [in] the 32-bit unsigned long to make signed
 * @return the 32-bit signed equivalent
 */
static VALUE amp_fixnum_to_signed_32(VALUE self) {
    VALUE result = rb_int_new((int32_t)FIX2LONG(self));
    return result;
}

/**
 * Byte-swaps a 64-bit bignum.
 * Bignum arithmetic is quite, quite slow. By implementing this in C, we save ourselves
 * innumerable cycles.
 * 
 * @param self [in] the bignum that needs byte swapping
 * @return the byte-swapped bignum (or not swapped if host is big-endian)
 */
static VALUE amp_bignum_byte_swap_64(VALUE self) {
    VALUE result = self;
    if (little_endian) {
    uint64_t val = rb_big2ull(self);
    val = (((val >> 56)) | ((val & 0x00FF000000000000ull) >> 40) |
         ((val & 0x0000FF0000000000ull) >> 24) | ((val & 0x000000FF00000000ull) >> 8)  |
         ((val & 0x00000000FF000000) << 8 ) | ((val & 0x0000000000FF0000) << 24) |
         ((val & 0x000000000000FF00) << 40) | ((val & 0x00000000000000FF) << 56));
     result = rb_ull2inum(val);
    }
    return result;
}

/**
 * Converts a bignum to a signed, 32-bit value.
 * Converts an unsigned, 32-bit number to its signed equivalent. Since Ruby
 * doesn't have signed values readily available, this is much much faster in
 * C.
 *
 * @param self [in] the 32-bit unsigned long to make signed
 * @return the 32-bit signed equivalent
 */
static VALUE amp_bignum_to_signed_32(VALUE self) {
    VALUE result = rb_int_new((int32_t)rb_big2ulong(self));
    return result;
}

/**
 * Converts a bignum to a signed, 16-bit value.
 * Converts an unsigned, 16-bit number to its signed equivalent.
 * This should actually never be called, because bignums shouldn't
 * ever be used for 16-bit values. However, it's provided just to be safe.
 * Since Ruby doesn't have signed values readily available, this is much 
 * much faster in C.
 *
 * @param self [in] the 16-bit unsigned short to make signed
 * @return the 16-bit signed equivalent
 */
static VALUE amp_bignum_to_signed_16(VALUE self) {
    signed short val = (int16_t)rb_big2ulong(self); // cut off bytes
    VALUE result = rb_int_new(val);
    return result;
}

// constant symbols that our dirstate would like
static VALUE rb_sRemoved, rb_sUntracked, rb_sNormal, rb_sMerged, rb_sAdded;

/**
 * Converts an ascii value to a dirstate status symbol.
 * Converts a fixnum, which is an ascii value, to a symbol representing
 * a dirstate entry's status. Since we don't like passing around 'n', and
 * want to pass around :normal, we need a fast lookup for ascii value ->
 * symbol. The price we pay.
 *
 * @param self [in] the integer ascii value to convert
 * @return a symbol representation of the dirstate status
 */
static VALUE amp_integer_to_dirstate_symbol(VALUE self) {
    int val = NUM2INT(self);
    switch (val) {
        case 110: return rb_sNormal;   // 'n'
        case 63: return rb_sUntracked; // '?'
        case 97: return rb_sAdded;     // 'a'
        case 109: return rb_sMerged;   // 'm'
        case 114: return rb_sRemoved;  // 'r'
    }
    rb_raise(rb_eStandardError, "no known hg value for %d", val);
}

/**
 * Converts a string of hexademical into its binary representation.
 * Method on strings. When the data in the string is hexademical
 * (such as "DEADBEEF"), this method decodes the hex and converts
 * every 2 bytes into its 1-byte binary representation.
 *
 * @example "414243".unhexlify == "ABC"
 * @param self [in] the string object to unhexlify
 * @return A decoded, binary string
 */
static VALUE amp_string_unhexlify(VALUE self) {
    // lengths of our strings
    unsigned int len, out_len;
    VALUE out;
    // byte buffers that we'll work with when unhexlifying
    char *out_buf, *in_buf;
    char chk;
    
    len = RSTRING_LEN(self);
    // 2 hex bytes -> 1 unhexlified byte
    out_len = len / 2;
    out = rb_str_new(NULL, out_len);
    
    // mark it as modified otherwise the GC will wig out at us
    rb_str_modify(out);
    // snag some pointers so we can do bad things
    in_buf  = RSTRING_PTR(self);
    out_buf = RSTRING_PTR(out);
    
    while (len) {
        // first byte is multiplied by 16
        chk = *in_buf++;
        if (chk >= '0' && chk <= '9')
            *out_buf = 16 * (chk - '0');
        else if (chk >= 'A' && chk <= 'F')
            *out_buf = 16 * (chk - 'A' + 10);
        else if (chk >= 'a' && chk <= 'f')
            *out_buf = 16 * (chk - 'a' + 10);
        // second byte is just added to result
        chk = *in_buf++;
        if (chk >= '0' && chk <= '9')
            *out_buf += (chk - '0');
        else if (chk >= 'A' && chk <= 'F')
            *out_buf += (chk - 'A' + 10);
        else if (chk >= 'a' && chk <= 'f')
            *out_buf += (chk - 'a' + 10);
        out_buf++;
        // 2 hex bytes down
        len -= 2;
    }
    return out;
}

/**
 * Initializes the Support module's C extension.
 * This function is the entry point to the module - when the code is require'd,
 * this function is run. All we need to do is add the new methods, and look up the
 * symbols for to_dirstate_symbol.
 */
void Init_Support() {
    if (little_endian == -1) little_endian = (ntohl(8) != 8);

    // methods added to String class
    rb_define_method(rb_cString, "unhexlify", amp_string_unhexlify, 0);
    
    // methods added to the Bignum class
    rb_define_method(rb_cBignum, "byte_swap_64", amp_bignum_byte_swap_64, 0);
    rb_define_method(rb_cBignum, "to_signed_32", amp_bignum_to_signed_32, 0);
    rb_define_method(rb_cBignum, "to_signed_16", amp_bignum_to_signed_16, 0);

    // methods added to the Fixnum class
    rb_define_method(rb_cFixnum, "byte_swap_64", amp_fixnum_byte_swap_64, 0);
    rb_define_method(rb_cFixnum, "to_signed_32", amp_fixnum_to_signed_32, 0);
    rb_define_method(rb_cFixnum, "to_signed_16", amp_fixnum_to_signed_16, 0);
    
    // Since symbols are only ever created once, let's look them up now, and never
    // look them up again!
    rb_sRemoved   = ID2SYM(rb_intern("removed"));
    rb_sUntracked = ID2SYM(rb_intern("untracked"));
    rb_sNormal    = ID2SYM(rb_intern("normal"));
    rb_sMerged    = ID2SYM(rb_intern("merged"));
    rb_sAdded     = ID2SYM(rb_intern("added"));
    
    // method added to the Integer class
    rb_define_method(rb_cInteger, "to_dirstate_symbol", amp_integer_to_dirstate_symbol, 0);
}
