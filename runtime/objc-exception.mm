/*
 * Copyright (c) 2002-2007 Apple Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 * 
 * This file contains Original Code and/or Modifications of Original Code
 * as defined in and that are subject to the Apple Public Source License
 * Version 2.0 (the 'License'). You may not use this file except in
 * compliance with the License. Please obtain a copy of the License at
 * http://www.opensource.apple.com/apsl/ and read it before using this
 * file.
 * 
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE, QUIET ENJOYMENT OR NON-INFRINGEMENT.
 * Please see the License for the specific language governing rights and
 * limitations under the License.
 * 
 * @APPLE_LICENSE_HEADER_END@
 */

/***********************************************************************
* 64-bit implementation.
**********************************************************************/

#include "objc-private.h"
#include <objc/objc-abi.h>
#include <objc/objc-exception.h>
#include <objc/NSObject.h>

#if !TARGET_OS_EXCLAVEKIT
#include <execinfo.h>
#endif

// unwind library types and functions
// Mostly adapted from Itanium C++ ABI: Exception Handling
//   http://www.codesourcery.com/cxx-abi/abi-eh.html

struct _Unwind_Exception;
struct _Unwind_Context;

typedef int _Unwind_Action;
enum : _Unwind_Action {
    _UA_SEARCH_PHASE = 1, 
    _UA_CLEANUP_PHASE = 2, 
    _UA_HANDLER_FRAME = 4, 
    _UA_FORCE_UNWIND = 8
};

typedef int _Unwind_Reason_Code;
enum : _Unwind_Reason_Code {
    _URC_NO_REASON = 0,
    _URC_FOREIGN_EXCEPTION_CAUGHT = 1,
    _URC_FATAL_PHASE2_ERROR = 2,
    _URC_FATAL_PHASE1_ERROR = 3,
    _URC_NORMAL_STOP = 4,
    _URC_END_OF_STACK = 5,
    _URC_HANDLER_FOUND = 6,
    _URC_INSTALL_CONTEXT = 7,
    _URC_CONTINUE_UNWIND = 8
};

struct dwarf_eh_bases
{
    uintptr_t tbase;
    uintptr_t dbase;
    uintptr_t func;
};

OBJC_EXTERN uintptr_t _Unwind_GetIP (struct _Unwind_Context *);
OBJC_EXTERN uintptr_t _Unwind_GetCFA (struct _Unwind_Context *);
OBJC_EXTERN uintptr_t _Unwind_GetLanguageSpecificData(struct _Unwind_Context *);


// C++ runtime types and functions
// copied from cxxabi.h

OBJC_EXTERN void *__cxa_allocate_exception(size_t thrown_size);
OBJC_EXTERN void __cxa_throw(void *exc, void *typeinfo, void (*destructor)(void *)) __attribute__((noreturn));
OBJC_EXTERN void *__cxa_begin_catch(void *exc);
OBJC_EXTERN void __cxa_end_catch(void);
OBJC_EXTERN void __cxa_rethrow(void);
OBJC_EXTERN void *__cxa_current_exception_type(void);

#if SUPPORT_ZEROCOST_EXCEPTIONS
#   define CXX_PERSONALITY __gxx_personality_v0
#else
#   define CXX_PERSONALITY __gxx_personality_sj0
#endif

OBJC_EXTERN _Unwind_Reason_Code 
CXX_PERSONALITY(int version,
                _Unwind_Action actions,
                uint64_t exceptionClass,
                struct _Unwind_Exception *exceptionObject,
                struct _Unwind_Context *context);


// objc's internal exception types and data

struct objc_typeinfo {
    // Position of vtable and name fields must match C++ typeinfo object
    const void ** __ptrauth_cxx_vtable_pointer vtable;  // objc_ehtype_vtable+2
    const char *name;     // c++ typeinfo string

    Class cls_unremapped;
};

struct objc_exception {
    id obj;
    struct objc_typeinfo tinfo;
};

extern "C" {

__attribute__((used))
void _objc_exception_noop(void) { }
__attribute__((used))
bool _objc_exception_false(void) { return 0; }
// bool _objc_exception_true(void) { return 1; }
__attribute__((used))
void _objc_exception_abort1(void) {
    _objc_fatal("unexpected call into objc exception typeinfo vtable %d", 1);
}
__attribute__((used))
void _objc_exception_abort2(void) {
    _objc_fatal("unexpected call into objc exception typeinfo vtable %d", 2);
}
__attribute__((used))
void _objc_exception_abort3(void) {
    _objc_fatal("unexpected call into objc exception typeinfo vtable %d", 3);
}
__attribute__((used))
void _objc_exception_abort4(void) {
    _objc_fatal("unexpected call into objc exception typeinfo vtable %d", 4);
}
__attribute__((used))
bool _objc_exception_do_catch(struct objc_typeinfo *catch_tinfo,
                              struct objc_typeinfo *throw_tinfo,
                              void **throw_obj_p,
                              unsigned outer);
}

// C++ pointers to vtables are signed with no extra data.
// C++ vtable entries are signed with a number derived from the function name.
// For this fake vtable, we hardcode number as deciphered from the
// assembly output during libc++abi's build.
#if __has_feature(ptrauth_calls)
#   define VTABLE_PTR_AUTH      "@AUTH(da, 0)"
#   define VTABLE_ENTRY_AUTH(x) "@AUTH(ia," #x ",addr)"
#else
#   define VTABLE_PTR_AUTH      ""
#   define VTABLE_ENTRY_AUTH(x) ""
#endif

#if __LP64__
#   define PTR ".quad "
#   define TWOPTRSIZE "16"
#else
#   define PTR ".long "
#   define TWOPTRSIZE "8"
#endif

// Hand-built vtable for objc exception typeinfo.
// "OLD" is GNU libcpp, "NEW" is libc++abi.

asm(
    "\n .cstring"
    "\n l_.id_str: .asciz \"id\""

    "\n .section __DATA,__const"
    "\n .globl _OBJC_EHTYPE_id"
    "\n .globl _objc_ehtype_vtable"
    "\n .p2align 4"

    "\n _OBJC_EHTYPE_id:"
    "\n  " PTR "(_objc_ehtype_vtable+" TWOPTRSIZE ") "      VTABLE_PTR_AUTH
    "\n  " PTR "l_.id_str"
    "\n  " PTR "0"

    "\n _objc_ehtype_vtable:"
    "\n  " PTR "0"
    // typeinfo's typeinfo - fixme hack
    "\n  " PTR "_OBJC_EHTYPE_id"
    // destructor and in-place destructor
    "\n  " PTR "__objc_exception_noop"      VTABLE_ENTRY_AUTH(52634)
    "\n  " PTR "__objc_exception_noop"      VTABLE_ENTRY_AUTH(10344)
    // OLD __is_pointer_p
    "\n  " PTR "__objc_exception_noop"      VTABLE_ENTRY_AUTH(6889)
    // OLD __is_function_p
    "\n  " PTR "__objc_exception_noop"      VTABLE_ENTRY_AUTH(23080)
    // OLD __do_catch,  NEW can_catch
    "\n  " PTR "__objc_exception_do_catch"  VTABLE_ENTRY_AUTH(27434)
    // OLD __do_upcast, NEW search_above_dst
    "\n  " PTR "__objc_exception_false"     VTABLE_ENTRY_AUTH(48481)
    //                  NEW search_below_dst
    "\n  " PTR "__objc_exception_false"     VTABLE_ENTRY_AUTH(41165)
    // NEW has_unambiguous_public_base (fixme need this?)
    "\n  " PTR "__objc_exception_abort1"    VTABLE_ENTRY_AUTH(14357)
    // paranoia: die if libcxxabi adds anything else
    "\n  " PTR "__objc_exception_abort2"
    "\n  " PTR "__objc_exception_abort3"
    "\n  " PTR "__objc_exception_abort4"
    );



/***********************************************************************
* Foundation customization
**********************************************************************/

/***********************************************************************
* _objc_default_exception_preprocessor
* Default exception preprocessor. Expected to be overridden by Foundation.
**********************************************************************/
static id _objc_default_exception_preprocessor(id exception)
{
    return exception;
}
static objc_exception_preprocessor ptrauth_objc_exception_preprocessor exception_preprocessor = _objc_default_exception_preprocessor;


/***********************************************************************
* _objc_default_exception_matcher
* Default exception matcher. Expected to be overridden by Foundation.
**********************************************************************/
static int _objc_default_exception_matcher(Class catch_cls, id exception)
{
    Class cls;
    for (cls = exception->getIsa();
         cls != nil; 
         cls = cls->getSuperclass())
    {
        if (cls == catch_cls) return 1;
    }

    return 0;
}
static objc_exception_matcher ptrauth_objc_exception_matcher exception_matcher = _objc_default_exception_matcher;


/***********************************************************************
* _objc_default_uncaught_exception_handler
* Default uncaught exception handler. Expected to be overridden by Foundation.
**********************************************************************/
static void _objc_default_uncaught_exception_handler(id exception)
{
}
static objc_uncaught_exception_handler ptrauth_objc_uncaught_exception_handler uncaught_handler = _objc_default_uncaught_exception_handler;


/***********************************************************************
* objc_setExceptionPreprocessor
* Set a handler for preprocessing Objective-C exceptions. 
* Returns the previous handler. 
**********************************************************************/
objc_exception_preprocessor
objc_setExceptionPreprocessor(objc_exception_preprocessor fn)
{
    objc_exception_preprocessor result = exception_preprocessor;
    exception_preprocessor = fn;
    return result;
}


/***********************************************************************
* objc_setExceptionMatcher
* Set a handler for matching Objective-C exceptions. 
* Returns the previous handler. 
**********************************************************************/
objc_exception_matcher
objc_setExceptionMatcher(objc_exception_matcher fn)
{
    objc_exception_matcher result = exception_matcher;
    exception_matcher = fn;
    return result;
}


/***********************************************************************
* objc_setUncaughtExceptionHandler
* Set a handler for uncaught Objective-C exceptions. 
* Returns the previous handler. 
**********************************************************************/
objc_uncaught_exception_handler 
objc_setUncaughtExceptionHandler(objc_uncaught_exception_handler fn)
{
    objc_uncaught_exception_handler result = uncaught_handler;
    uncaught_handler = fn;
    return result;
}


/***********************************************************************
* Exception personality
**********************************************************************/

static void call_alt_handlers(struct _Unwind_Context *ctx);

_Unwind_Reason_Code 
__objc_personality_v0(int version,
                      _Unwind_Action actions,
                      uint64_t exceptionClass,
                      struct _Unwind_Exception *exceptionObject,
                      struct _Unwind_Context *context)
{
    bool unwinding = ((actions & _UA_CLEANUP_PHASE)  ||  
                      (actions & _UA_FORCE_UNWIND));

    if (PrintExceptions) {
        _objc_inform("EXCEPTIONS: %s through frame [ip=%p sp=%p] "
                     "for exception %p", 
                     unwinding ? "unwinding" : "searching", 
                     (void*)(_Unwind_GetIP(context)-1),
                     (void*)_Unwind_GetCFA(context), exceptionObject);
    }

    // If we're executing the unwind, call this frame's alt handlers, if any.
    if (unwinding) {
        call_alt_handlers(context);
    }

    // Let C++ handle the unwind itself.
    return CXX_PERSONALITY(version, actions, exceptionClass, 
                           exceptionObject, context);
}


/***********************************************************************
* Compiler ABI
**********************************************************************/

static void _objc_exception_destructor(void *exc_gen) 
{
    // Release the retain from objc_exception_throw().

    struct objc_exception *exc = (struct objc_exception *)exc_gen;
    id obj = exc->obj;

    if (PrintExceptions) {
        _objc_inform("EXCEPTIONS: releasing completed exception %p (object %p, a %s)", 
                     exc, obj, object_getClassName(obj));
    }

    [obj release];
}


void objc_exception_throw(id obj)
{
    struct objc_exception *exc = (struct objc_exception *)
        __cxa_allocate_exception(sizeof(struct objc_exception));

    obj = (*exception_preprocessor)(obj);

    // Retain the exception object during unwinding
    // because otherwise an autorelease pool pop can cause a crash
    [obj retain];

    exc->obj = obj;
    exc->tinfo.vtable = objc_ehtype_vtable+2;
    exc->tinfo.name = object_getClassName(obj);
    exc->tinfo.cls_unremapped = obj ? obj->getIsa() : Nil;

    if (PrintExceptions) {
        _objc_inform("EXCEPTIONS: throwing %p (object %p, a %s)", 
                     exc, (void*)obj, object_getClassName(obj));
    }

#if !TARGET_OS_EXCLAVEKIT
    if (PrintExceptionThrow) {
        if (!PrintExceptions)
            _objc_inform("EXCEPTIONS: throwing %p (object %p, a %s)", 
                         exc, (void*)obj, object_getClassName(obj));
        void* callstack[500];
        int frameCount = backtrace(callstack, 500);
        backtrace_symbols_fd(callstack, frameCount, fileno(stderr));
    }
#endif

    OBJC_RUNTIME_OBJC_EXCEPTION_THROW(obj);  // dtrace probe to log throw activity

    __cxa_throw(exc, &exc->tinfo, &_objc_exception_destructor);
    __builtin_trap();
}


void objc_exception_rethrow(void)
{
    // exception_preprocessor doesn't get another bite of the apple
    if (PrintExceptions) {
        _objc_inform("EXCEPTIONS: rethrowing current exception");
    }

    OBJC_RUNTIME_OBJC_EXCEPTION_RETHROW(); // dtrace probe to log throw activity.

    __cxa_rethrow();
    __builtin_trap();
}


id objc_begin_catch(void *exc_gen)
{
    if (PrintExceptions) {
        _objc_inform("EXCEPTIONS: handling exception %p at %p", 
                     exc_gen, __builtin_return_address(0));
    }
    // NOT actually an id in the catch(...) case!
    return (id)__cxa_begin_catch(exc_gen);
}


void objc_end_catch(void)
{
    if (PrintExceptions) {
        _objc_inform("EXCEPTIONS: finishing handler");
    }
    __cxa_end_catch();
}


// `outer` is not passed by the new libcxxabi
bool _objc_exception_do_catch(struct objc_typeinfo *catch_tinfo, 
                              struct objc_typeinfo *throw_tinfo, 
                              void **throw_obj_p, 
                              unsigned outer UNAVAILABLE_ATTRIBUTE)
{
    id exception;

    if (throw_tinfo->vtable != objc_ehtype_vtable+2) {
        // Only objc types can be caught here.
        if (PrintExceptions) _objc_inform("EXCEPTIONS: skipping catch(?)");
        return false;
    }

    // Adjust exception pointer.
    // Old libcppabi: we lied about __is_pointer_p() so we have to do it here
    // New libcxxabi: we have to do it here regardless
    *throw_obj_p = **(void***)throw_obj_p;

    // `catch (id)` always catches objc types.
    if (catch_tinfo == &OBJC_EHTYPE_id) {
        if (PrintExceptions) _objc_inform("EXCEPTIONS: catch(id)");
        return true;
    }

    exception = *(id *)throw_obj_p;

    Class handler_cls = _class_remap(catch_tinfo->cls_unremapped);
    if (!handler_cls) {
        // catch handler's class is weak-linked and missing. Not a match.
    }
    else if ((*exception_matcher)(handler_cls, exception)) {
        if (PrintExceptions) _objc_inform("EXCEPTIONS: catch(%s)", 
                                          handler_cls->nameForLogging());
        return true;
    }

    if (PrintExceptions) _objc_inform("EXCEPTIONS: skipping catch(%s)", 
                                      handler_cls->nameForLogging());

    return false;
}


/***********************************************************************
* _objc_terminate
* Custom std::terminate handler.
*
* The uncaught exception callback is implemented as a std::terminate handler. 
* 1. Check if there's an active exception
* 2. If so, check if it's an Objective-C exception
* 3. If so, call our registered callback with the object.
* 4. Finally, call the previous terminate handler.
**********************************************************************/
static void (*old_terminate)(void) = nil;
static void _objc_terminate(void)
{
    if (PrintExceptions) {
        _objc_inform("EXCEPTIONS: terminating");
    }

    if (! __cxa_current_exception_type()) {
        // No current exception.
        (*old_terminate)();
    }
    else {
        // There is a current exception. Check if it's an objc exception.
        @try {
            __cxa_rethrow();
        } @catch (id e) {
            // It's an objc object. Call Foundation's handler, if any.
            (*uncaught_handler)((id)e);
            (*old_terminate)();
        } @catch (...) {
            // It's not an objc object. Continue to C++ terminate.
            (*old_terminate)();
        }
    }
}


/***********************************************************************
* objc_terminate
* Calls std::terminate for clients who don't link to C++ themselves.
* Called by the compiler if an exception is thrown 
* from a context where exceptions may not be thrown. 
**********************************************************************/
void objc_terminate(void)
{
    std::terminate();
}


/***********************************************************************
* alt handler support - zerocost implementation only
**********************************************************************/

#if !SUPPORT_ALT_HANDLERS

void _destroyAltHandlerList(struct alt_handler_list *list)
{
}

static void call_alt_handlers(struct _Unwind_Context *ctx)
{
    // unsupported in sjlj environments
}

#else

#include <libunwind.h>

#if !TARGET_OS_EXCLAVEKIT
#include <execinfo.h>
#include <dispatch/dispatch.h>
#endif

// Dwarf eh data encodings
#define DW_EH_PE_omit      0xff  // no data follows

#define DW_EH_PE_absptr    0x00
#define DW_EH_PE_uleb128   0x01
#define DW_EH_PE_udata2    0x02
#define DW_EH_PE_udata4    0x03
#define DW_EH_PE_udata8    0x04
#define DW_EH_PE_sleb128   0x09
#define DW_EH_PE_sdata2    0x0A
#define DW_EH_PE_sdata4    0x0B
#define DW_EH_PE_sdata8    0x0C

#define DW_EH_PE_pcrel     0x10
#define DW_EH_PE_textrel   0x20
#define DW_EH_PE_datarel   0x30
#define DW_EH_PE_funcrel   0x40
#define DW_EH_PE_aligned   0x50  // fixme

#define DW_EH_PE_indirect  0x80  // gcc extension


/***********************************************************************
* read_uleb
* Read a LEB-encoded unsigned integer from the address stored in *pp.
* Increments *pp past the bytes read.
* Adapted from DWARF Debugging Information Format 1.1, appendix 4
**********************************************************************/
static uintptr_t read_uleb(uintptr_t *pp)
{
    uintptr_t result = 0;
    uintptr_t shift = 0;
    unsigned char byte;
    do {
        byte = *(const unsigned char *)(*pp)++;
        result |= (byte & 0x7f) << shift;
        shift += 7;
    } while (byte & 0x80);
    return result;
}


/***********************************************************************
* read_sleb
* Read a LEB-encoded signed integer from the address stored in *pp.
* Increments *pp past the bytes read.
* Adapted from DWARF Debugging Information Format 1.1, appendix 4
**********************************************************************/
static intptr_t read_sleb(uintptr_t *pp)
{
    uintptr_t result = 0;
    uintptr_t shift = 0;
    unsigned char byte;
    do {
        byte = *(const unsigned char *)(*pp)++;
        result |= (byte & 0x7f) << shift;
        shift += 7;
    } while (byte & 0x80);
    if ((shift < 8*sizeof(intptr_t))  &&  (byte & 0x40)) {
        result |= ((intptr_t)-1) << shift;
    }
    return result;
}


/***********************************************************************
* read_address
* Reads an encoded address from the address stored in *pp.
* Increments *pp past the bytes read.
* The data is interpreted according to the given dwarf encoding 
* and base addresses.
**********************************************************************/
static uintptr_t read_address(uintptr_t *pp, 
                              const struct dwarf_eh_bases *bases, 
                              unsigned char encoding)
{
    uintptr_t result = 0;
    uintptr_t oldp = *pp;

    // fixme need DW_EH_PE_aligned?

#define READ(type) \
    result = *(type *)(*pp); \
    *pp += sizeof(type);

    if (encoding == DW_EH_PE_omit) return 0;

    switch (encoding & 0x0f) {
    case DW_EH_PE_absptr:
        READ(uintptr_t);
        break;
    case DW_EH_PE_uleb128:
        result = read_uleb(pp);
        break;
    case DW_EH_PE_udata2:
        READ(uint16_t);
        break;
    case DW_EH_PE_udata4:
        READ(uint32_t);
        break;
#if __LP64__
    case DW_EH_PE_udata8:
        READ(uint64_t);
        break;
#endif
    case DW_EH_PE_sleb128:
        result = read_sleb(pp);
        break;
    case DW_EH_PE_sdata2:
        READ(int16_t);
        break;
    case DW_EH_PE_sdata4:
        READ(int32_t);
        break;
#if __LP64__
    case DW_EH_PE_sdata8:
        READ(int64_t);
        break;
#endif
    default:
        _objc_inform("unknown DWARF EH encoding 0x%x at %p", 
                     encoding, (void *)*pp);
        break;
    }

#undef READ

    if (result) {
        switch (encoding & 0x70) {
        case DW_EH_PE_pcrel:
            // fixme correct?
            result += (uintptr_t)oldp;
            break;
        case DW_EH_PE_textrel:
            result += bases->tbase;
            break;
        case DW_EH_PE_datarel:
            result += bases->dbase;
            break;
        case DW_EH_PE_funcrel:
            result += bases->func;
            break;
        case DW_EH_PE_aligned:
            _objc_inform("unknown DWARF EH encoding 0x%x at %p", 
                         encoding, (void *)*pp);
            break;
        default:
            // no adjustment
            break;
        }

        if (encoding & DW_EH_PE_indirect) {
            result = *(uintptr_t *)result;
        }
    }

    return (uintptr_t)result;
}


struct frame_ips {
    uintptr_t start;
    uintptr_t end;
};
struct frame_range {
    uintptr_t ip_start;
    uintptr_t ip_end;
    uintptr_t cfa;
    // precise ranges within ip_start..ip_end; nil or {0,0} terminated
    frame_ips *ips;
};


static bool isObjCExceptionCatcher(uintptr_t lsda, uintptr_t ip, 
                                   const struct dwarf_eh_bases* bases,
                                   struct frame_range *frame)
{
    unsigned char LPStart_enc = *(const unsigned char *)lsda++;    

    if (LPStart_enc != DW_EH_PE_omit) {
        read_address(&lsda, bases, LPStart_enc); // LPStart
    }

    unsigned char TType_enc = *(const unsigned char *)lsda++;
    if (TType_enc != DW_EH_PE_omit) {
        read_uleb(&lsda);  // TType
    }

    unsigned char call_site_enc = *(const unsigned char *)lsda++;
    uintptr_t length = read_uleb(&lsda);
    uintptr_t call_site_table = lsda;
    uintptr_t call_site_table_end = call_site_table + length;
    uintptr_t action_record_table = call_site_table_end;

    uintptr_t action_record = 0;
    uintptr_t p = call_site_table;

    uintptr_t try_start;
    uintptr_t try_end;
    uintptr_t try_landing_pad;

    while (p < call_site_table_end) {
        uintptr_t start   = read_address(&p, bases, call_site_enc)+bases->func;
        uintptr_t len     = read_address(&p, bases, call_site_enc);
        uintptr_t pad     = read_address(&p, bases, call_site_enc);
        uintptr_t action  = read_uleb(&p);

        if (ip < start) {
            // no more source ranges
            return false;
        } 
        else if (ip < start + len) {
            // found the range
            if (!pad) return false;  // ...but it has no landing pad
            // found the landing pad
            action_record = action ? action_record_table + action - 1 : 0;
            try_start = start;
            try_end = start + len;
            try_landing_pad = pad;
            break;
        }        
    }
    
    if (!action_record) return false;  // no catch handlers

    // has handlers, destructors, and/or throws specifications
    // Use this frame if it has any handlers
    bool has_handler = false;
    p = action_record;
    intptr_t offset;
    do {
        intptr_t filter = read_sleb(&p);
        uintptr_t temp = p;
        offset = read_sleb(&temp);
        p += offset;
        
        if (filter < 0) {
            // throws specification - ignore
        } else if (filter == 0) {
            // destructor - ignore
        } else /* filter >= 0 */ {
            // catch handler - use this frame
            has_handler = true;
            break;
        }
    } while (offset);

    if (!has_handler) return false;
    
    // Count the number of source ranges with the same landing pad as our match
    unsigned int range_count = 0;
    p = call_site_table;
    while (p < call_site_table_end) {
                /*start*/  read_address(&p, bases, call_site_enc)/*+bases->func*/;
                /*len*/    read_address(&p, bases, call_site_enc);
        uintptr_t pad    = read_address(&p, bases, call_site_enc);
                /*action*/ read_uleb(&p);
        
        if (pad == try_landing_pad) {
            range_count++;
        }
    }

    if (range_count == 1) {
        // No other source ranges with the same landing pad. We're done here.
        frame->ips = nil;
    }
    else {
        // Record all ranges with the same landing pad as our match.
        frame->ips = (frame_ips *)
            malloc((range_count + 1) * sizeof(frame->ips[0]));
        unsigned int r = 0;
        p = call_site_table;
        while (p < call_site_table_end) {
            uintptr_t start  = read_address(&p, bases, call_site_enc)+bases->func;
            uintptr_t len    = read_address(&p, bases, call_site_enc);
            uintptr_t pad    = read_address(&p, bases, call_site_enc);
                    /*action*/ read_uleb(&p);
            
            if (pad == try_landing_pad) {
                if (start < try_start) try_start = start;
                if (start+len > try_end) try_end = start+len;
                frame->ips[r].start = start;
                frame->ips[r].end = start+len;
                r++;
            }
        }

        frame->ips[r].start = 0;
        frame->ips[r].end = 0;
    }

    frame->ip_start = try_start;
    frame->ip_end = try_end;

    return true;
}


static struct frame_range findHandler(void)
{
    // walk stack looking for frame with objc catch handler
    unw_context_t    uc;
    unw_cursor_t    cursor; 
    unw_proc_info_t    info;
    unw_getcontext(&uc);
    unw_init_local(&cursor, &uc);
    uintptr_t objc_personality
        = (uintptr_t)ptrauth_strip((void *)__objc_personality_v0,
                                   ptrauth_key_function_pointer);

    while ( (unw_step(&cursor) > 0) && (unw_get_proc_info(&cursor, &info) == UNW_ESUCCESS) ) {
        // must use objc personality handler
        if ( info.handler != objc_personality)
            continue;
        // must have landing pad
        if ( info.lsda == 0 )
            continue;
        // must have landing pad that catches objc exceptions
        struct dwarf_eh_bases bases;
        bases.tbase = 0;  // from unwind-dw2-fde-darwin.c:examine_objects()
        bases.dbase = 0;  // from unwind-dw2-fde-darwin.c:examine_objects()
        bases.func = info.start_ip;
        unw_word_t ip;
        unw_get_reg(&cursor, UNW_REG_IP, &ip);
        ip = (unw_word_t)ptrauth_strip((void *)ip,
                                       ptrauth_key_function_pointer);
        ip -= 1;
        struct frame_range try_range = {0, 0, 0, 0};
        if ( isObjCExceptionCatcher(info.lsda, ip, &bases, &try_range) ) {
            unw_word_t cfa;
            unw_get_reg(&cursor, UNW_REG_SP, &cfa);
            try_range.cfa = cfa;
            return try_range;
        }
    }

    return (struct frame_range){0, 0, 0, 0};
}


// This data structure assumes the number of 
// active alt handlers per frame is small.

// for OBJC_DEBUG_ALT_HANDLERS, record the call to objc_addExceptionHandler.
#define BACKTRACE_COUNT 46
#define THREADNAME_COUNT 64
struct alt_handler_debug {
    uintptr_t token;
    int backtraceSize;
    void *backtrace[BACKTRACE_COUNT];
    char thread[THREADNAME_COUNT];
    char queue[THREADNAME_COUNT];
};

struct alt_handler_data {
    struct frame_range frame;
    objc_exception_handler fn;
    void *context;
    struct alt_handler_debug *debug;
};

struct alt_handler_list {
    unsigned int allocated;
    unsigned int used;
    struct alt_handler_data *handlers;
    struct alt_handler_list *next_DEBUGONLY;
};

static struct alt_handler_list *DebugLists;
static uintptr_t DebugCounter;

__attribute__((noinline, noreturn))
void alt_handler_error(uintptr_t token);

static struct alt_handler_list *
fetch_handler_list(bool create)
{
    _objc_pthread_data *data = _objc_fetch_pthread_data(create);
    if (!data) return nil;

    struct alt_handler_list *list = data->handlerList;
    if (!list) {
        if (!create) return nil;
        list = (struct alt_handler_list *)calloc(1, sizeof(*list));
        data->handlerList = list;

        if (DebugAltHandlers) {
            // Save this list so the debug code can find it from other threads
            mutex_locker_t lock(AltHandlerDebugLock);
            list->next_DEBUGONLY = DebugLists;
            DebugLists = list;
        }
    }

    return list;
}


void _destroyAltHandlerList(struct alt_handler_list *list)
{
    if (list) {
        if (DebugAltHandlers) {
            // Detach from the list-of-lists.
            mutex_locker_t lock(AltHandlerDebugLock);
            struct alt_handler_list **listp = &DebugLists;
            while (*listp && *listp != list) listp = &(*listp)->next_DEBUGONLY;
            if (*listp) *listp = (*listp)->next_DEBUGONLY;
        }

        if (list->handlers) {
            for (unsigned int i = 0; i < list->allocated; i++) {
                if (list->handlers[i].frame.ips) {
                    free(list->handlers[i].frame.ips);
                }
            }
            free(list->handlers);
        }
        free(list);
    }
}


uintptr_t objc_addExceptionHandler(objc_exception_handler fn, void *context)
{ 
    // Find the closest enclosing frame with objc catch handlers
    struct frame_range target_frame = findHandler();
    if (!target_frame.ip_start) {
        // No suitable enclosing handler found.
        return 0;
    }

    // Record this alt handler for the discovered frame.
    struct alt_handler_list *list = fetch_handler_list(YES);
    unsigned int i = 0;

    if (list->used == list->allocated) {
        list->allocated = list->allocated*2 ?: 4;
        list->handlers = (struct alt_handler_data *)
            realloc(list->handlers, 
                              list->allocated * sizeof(list->handlers[0]));
        memset(&list->handlers[list->used], 0, (list->allocated - list->used) * sizeof(list->handlers[0]));
        i = list->used;
    }
    else {
        for (i = 0; i < list->allocated; i++) {
            if (list->handlers[i].frame.ip_start == 0  &&  
                list->handlers[i].frame.ip_end == 0  &&  
                list->handlers[i].frame.cfa == 0) 
            {
                break;
            }
        }
        if (i == list->allocated) {
            _objc_fatal("alt handlers in objc runtime are buggy!");
        }
    }

    struct alt_handler_data *data = &list->handlers[i];

    data->frame = target_frame;
    data->fn = fn;
    data->context = context;
    list->used++;

    uintptr_t token = i+1;

#if !TARGET_OS_EXCLAVEKIT
    if (DebugAltHandlers) {
        // Record backtrace in case this handler is misused later.
        mutex_locker_t lock(AltHandlerDebugLock);

        token = DebugCounter++;
        if (token == 0) token = DebugCounter++;

        if (!data->debug) {
            data->debug = (struct alt_handler_debug *)
                calloc(sizeof(*data->debug), 1);
        } else {
            memset(data->debug, 0, sizeof(*data->debug));
        }

        pthread_getname_np(objc_thread_self(), data->debug->thread, THREADNAME_COUNT);
        strlcpy(data->debug->queue,
                dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL),
                THREADNAME_COUNT);
        data->debug->backtraceSize = 
            backtrace(data->debug->backtrace, BACKTRACE_COUNT);
        data->debug->token = token;
    }
#endif // !TARGET_OS_EXCLAVEKIT

    if (PrintAltHandlers) {
        _objc_inform("ALT HANDLERS: installing alt handler #%lu %p(%p) on "
                     "frame [ip=%p..%p sp=%p]", (unsigned long)token, 
                     data->fn, data->context, (void *)data->frame.ip_start, 
                     (void *)data->frame.ip_end, (void *)data->frame.cfa);
        if (data->frame.ips) {
            unsigned int r = 0;
            while (1) {
                uintptr_t start = data->frame.ips[r].start;
                uintptr_t end = data->frame.ips[r].end;
                r++;
                if (start == 0  &&  end == 0) break;
                _objc_inform("ALT HANDLERS:     ip=%p..%p", 
                             (void*)start, (void*)end);
            }
        }
    }

    if (list->used > 1000) {
        static int warned = 0;
        if (!warned) {
            _objc_inform("ALT HANDLERS: *** over 1000 alt handlers installed; "
                         "this is probably a bug");
            warned = 1;
        }
    }

    return token;
}


void objc_removeExceptionHandler(uintptr_t token)
{
    if (!token) {
        // objc_addExceptionHandler failed
        return;
    }
    
    struct alt_handler_list *list = fetch_handler_list(NO);
    if (!list  ||  !list->handlers) {
        // no alt handlers active
        alt_handler_error(token);
    }

    uintptr_t i = token-1;
    
    if (DebugAltHandlers) {
        // search for the token instead of using token-1
        for (i = 0; i < list->allocated; i++) {
            struct alt_handler_data *data = &list->handlers[i];
            if (data->debug  &&  data->debug->token == token) break;
        }
    }
    
    if (i >= list->allocated) {
        // token out of range
        alt_handler_error(token);
    }

    struct alt_handler_data *data = &list->handlers[i];

    if (data->frame.ip_start == 0  &&  data->frame.ip_end == 0  &&  data->frame.cfa == 0) {
        // token in range, but invalid
        alt_handler_error(token);
    }

    if (PrintAltHandlers) {
        _objc_inform("ALT HANDLERS: removing   alt handler #%lu %p(%p) on "
                     "frame [ip=%p..%p sp=%p]", (unsigned long)token, 
                     data->fn, data->context, (void *)data->frame.ip_start, 
                     (void *)data->frame.ip_end, (void *)data->frame.cfa);
    }

    if (data->debug) free(data->debug);
    if (data->frame.ips) free(data->frame.ips);
    memset(data, 0, sizeof(*data));
    list->used--;
}


BREAKPOINT_FUNCTION(
void objc_alt_handler_error(void));

__attribute__((noinline, noreturn))
void alt_handler_error(uintptr_t token)
{
    _objc_inform
        ("objc_removeExceptionHandler() called with unknown alt handler; "
         "this is probably a bug in multithreaded AppKit use. "
         "Set environment variable OBJC_DEBUG_ALT_HANDLERS=YES "
         "or break in objc_alt_handler_error() to debug.");

#if !TARGET_OS_EXCLAVEKIT
    if (DebugAltHandlers) {
        AltHandlerDebugLock.lock();
        
        // Search other threads' alt handler lists for this handler.
        struct alt_handler_list *list;
        for (list = DebugLists; list; list = list->next_DEBUGONLY) {
            unsigned h;
            for (h = 0; h < list->allocated; h++) {
                struct alt_handler_data *data = &list->handlers[h];
                if (data->debug  &&  data->debug->token == token) {
                    // found it
                    int i;
                    
                    // Build a string from the recorded backtrace
                    char *symbolString;
                    char **symbols = 
                        backtrace_symbols(data->debug->backtrace, 
                                          data->debug->backtraceSize);
                    size_t len = 1;
                    for (i = 0; i < data->debug->backtraceSize; i++){
                        len += 4 + strlen(symbols[i]) + 1;
                    }
                    symbolString = (char *)calloc(len, 1);
                    for (i = 0; i < data->debug->backtraceSize; i++){
                        strcat(symbolString, "    ");
                        strcat(symbolString, symbols[i]);
                        strcat(symbolString, "\n");
                    }
                    
                    free(symbols);
                    
                    _objc_inform_now_and_on_crash
                        ("The matching objc_addExceptionHandler() was called "
                         "by:\nThread '%s': Dispatch queue: '%s': \n%s", 
                         data->debug->thread, data->debug->queue, symbolString);

                    goto done;
                }
            }
        }
    done:   
        AltHandlerDebugLock.unlock();
    }
#endif // !TARGET_OS_EXCLAVEKIT

    objc_alt_handler_error();
    
    _objc_fatal
        ("objc_removeExceptionHandler() called with unknown alt handler; "
         "this is probably a bug in multithreaded AppKit use. ");
}

// called in order registered, to match 32-bit _NSAddAltHandler2
// fixme reverse registration order matches c++ destructors better
static void call_alt_handlers(struct _Unwind_Context *ctx)
{
    uintptr_t ip = _Unwind_GetIP(ctx) - 1;
    uintptr_t cfa = _Unwind_GetCFA(ctx);
    unsigned int i;
    
    struct alt_handler_list *list = fetch_handler_list(NO);
    if (!list  ||  list->used == 0) return;

    for (i = 0; i < list->allocated; i++) {
        struct alt_handler_data *data = &list->handlers[i];
        if (ip >= data->frame.ip_start  &&  ip < data->frame.ip_end  &&  data->frame.cfa == cfa) 
        {
            if (data->frame.ips) {
                unsigned int r = 0;
                bool found;
                while (1) {
                    uintptr_t start = data->frame.ips[r].start;
                    uintptr_t end = data->frame.ips[r].end;
                    r++;
                    if (start == 0  &&  end == 0) {
                        found = false;
                        break;
                    }
                    if (ip >= start  &&  ip < end) {
                        found = true; 
                        break;
                    }
                }
                if (!found) continue;
            }

            // Copy and clear before the callback, in case the 
            // callback manipulates the alt handler list.
            struct alt_handler_data copy = *data;
            memset(data, 0, sizeof(*data));
            list->used--;
            if (PrintExceptions || PrintAltHandlers) {
                _objc_inform("EXCEPTIONS: calling alt handler %p(%p) from "
                             "frame [ip=%p..%p sp=%p]", copy.fn, copy.context, 
                             (void *)copy.frame.ip_start, 
                             (void *)copy.frame.ip_end, 
                             (void *)copy.frame.cfa);
            }
            if (copy.fn) (*copy.fn)(nil, copy.context);
            if (copy.frame.ips) free(copy.frame.ips);
        }
    }
}

// SUPPORT_ALT_HANDLERS
#endif


/***********************************************************************
* exception_init
* Initialize libobjc's exception handling system.
* Called by map_images().
**********************************************************************/
void exception_init(void)
{
    old_terminate = std::set_terminate(&_objc_terminate);
}


// Define this everywhere even if it isn't used, to simplify fork() safety code
ExplicitInitLock<mutex_t> AltHandlerDebugLock;
