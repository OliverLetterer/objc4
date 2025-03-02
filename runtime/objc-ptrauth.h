/*
 * Copyright (c) 2017 Apple Inc.  All Rights Reserved.
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

#ifndef _OBJC_PTRAUTH_H_
#define _OBJC_PTRAUTH_H_

#include <objc/objc.h>

#include <bit>
#include <ptrauth.h>

// Workaround <rdar://problem/64531063> Definitions of ptrauth_sign_unauthenticated and friends generate unused variables warnings
#if __has_feature(ptrauth_calls)
#define UNUSED_WITHOUT_PTRAUTH
#else
#define UNUSED_WITHOUT_PTRAUTH __unused
#define __ptrauth(key, address, discriminator)
#endif

#if __has_feature(ptrauth_calls)
#else
#endif


#if __has_feature(ptrauth_calls)

// ptrauth modifier for tagged pointer class tables.
#define ptrauth_taggedpointer_table_entry \
    __ptrauth(ptrauth_key_process_dependent_data, 1, TAGGED_POINTER_TABLE_ENTRY_DISCRIMINATOR)

#define ptrauth_method_list_types \
    __ptrauth(ptrauth_key_process_dependent_data, 1, \
    ptrauth_string_discriminator("method_t::bigSigned::types"))

#define ptrauth_densemap_buckets \
    __ptrauth(ptrauth_key_process_dependent_data, 1, \
    ptrauth_string_discriminator("DenseMap::Buckets"))

#define ptrauth_loadImageCallback \
    __ptrauth(ptrauth_key_process_dependent_code, 1, \
    ptrauth_string_discriminator("objc_func_loadImage"))

#define ptrauth_loadImageCallback2 \
    __ptrauth(ptrauth_key_process_dependent_code, 1, \
    ptrauth_string_discriminator("objc_func_loadImage2"))

#define ptrauth_objc_exception_preprocessor \
    __ptrauth(ptrauth_key_process_independent_code, 1, \
    ptrauth_string_discriminator("objc_exception_preprocessor"))

#define ptrauth_objc_exception_matcher \
    __ptrauth(ptrauth_key_process_independent_code, 1, \
    ptrauth_string_discriminator("objc_exception_matcher"))

#define ptrauth_objc_uncaught_exception_handler \
    __ptrauth(ptrauth_key_process_independent_code, 1, \
    ptrauth_string_discriminator("objc_uncaught_exception_handler"))

#define ptrauth_badAllocHandler \
    __ptrauth(ptrauth_key_process_independent_code, 1, \
    ptrauth_string_discriminator("badAllocHandler"))

#define ptrauth_objc_forward_handler \
    __ptrauth(ptrauth_key_process_independent_code, 1, \
    ptrauth_string_discriminator("_objc_forward_handler"))

#else

#define ptrauth_taggedpointer_table_entry
#define ptrauth_method_list_types
#define ptrauth_densemap_buckets
#define ptrauth_loadImageCallback
#define ptrauth_loadImageCallback2
#define ptrauth_objc_exception_preprocessor
#define ptrauth_objc_exception_matcher
#define ptrauth_objc_uncaught_exception_handler
#define ptrauth_badAllocHandler
#define ptrauth_objc_forward_handler

#endif

// A combination ptrauth_auth_and_resign and bitcast, to avoid implicit
// re-signing operations when casting to/from function pointers when
// -fptrauth-function-pointer-type-discrimination is enabled. This produces
// better code than casting and using a 0 discriminator, as clang currently
// doesn't remove the redundant sign-then-auth that happens in the middle.
// rdar://110175155
#define bitcast_auth_and_resign(castType, value, oldKey, oldData, newKey, newData) \
    ptrauth_auth_and_resign(std::bit_cast<castType>(value), oldKey, oldData, newKey, newData)

// Method lists use process-independent signature for compatibility.
using MethodListIMP = IMP __ptrauth_objc_method_list_imp;

//
static inline struct method_t *_method_auth(Method mSigned) {
    if (!mSigned)
        return NULL;
    return (struct method_t *)ptrauth_auth_data(mSigned, ptrauth_key_process_dependent_data, METHOD_SIGNING_DISCRIMINATOR);
}

static inline Method _method_sign(struct method_t *m) {
    if (!m)
        return NULL;
    return (Method)ptrauth_sign_unauthenticated(m, ptrauth_key_process_dependent_data, METHOD_SIGNING_DISCRIMINATOR);
}

// A struct that wraps a pointer using the provided template.
// The provided Auth parameter is used to sign and authenticate
// the pointer as it is read and written.
template<typename T, typename Auth>
struct WrappedPtr {
private:
    T *ptr;

#if __BUILDING_OBJCDT__
    static T *sign(T *p, const void *addr __unused) {
        return p;
    }

    static T *auth(T *p, const void *addr __unused) {
        return ptrauth_strip(p, ptrauth_key_process_dependent_data);
    }
#else
    static T *sign(T *p, const void *addr) {
        return Auth::sign(p, addr);
    }

    static T *auth(T *p, const void *addr) {
        return Auth::auth(p, addr);
    }
#endif

public:
    WrappedPtr(T *p) {
        *this = p;
    }

    WrappedPtr(const WrappedPtr<T, Auth> &p) {
        *this = p;
    }

    WrappedPtr<T, Auth> &operator =(T *p) {
        ptr = sign(p, &ptr);
        return *this;
    }

    WrappedPtr<T, Auth> &operator =(const WrappedPtr<T, Auth> &p) {
        *this = (T *)p;
        return *this;
    }

    operator T*() const { return get(); }
    T *operator->() const { return get(); }

    T *get() const { return auth(ptr, &ptr); }

    // When asserts are enabled, ensure that we can read a byte from
    // the underlying pointer. This can be used to catch ptrauth
    // errors early for easier debugging.
    void validate() const {
#if !NDEBUG
        char *p = (char *)get();
        char dummy;
        memset_s(&dummy, 1, *p, 1);
        ASSERT(dummy == *p);
#endif
    }
};

// A "ptrauth" struct that just passes pointers through unchanged.
struct PtrauthRaw {
    template <typename T>
    static T sign(T ptr, __unused const void *address) {
        return ptr;
    }

    template <typename T>
    static T auth(T ptr, __unused const void *address) {
        return ptr;
    }
};

// A ptrauth struct that stores pointers raw, and strips ptrauth
// when reading.
struct PtrauthStrip {
    template <typename T>
    static T *sign(T *ptr, __unused const void *address) {
        return ptr;
    }

    template <typename T>
    static T *auth(T *ptr, __unused const void *address) {
        return ptrauth_strip(ptr, ptrauth_key_process_dependent_data);
    }
};

// A ptrauth struct that signs and authenticates pointers using the
// DB key with the given discriminator and address diversification.
template <unsigned discriminator, ptrauth_key key = ptrauth_key_process_dependent_data>
struct Ptrauth {
    template <typename T>
    static T *sign(T *ptr, UNUSED_WITHOUT_PTRAUTH const void *address) {
        if (!ptr)
            return nullptr;
        return ptrauth_sign_unauthenticated(ptr, key, ptrauth_blend_discriminator(address, discriminator));
    }

    template <typename T>
    static T *auth(T *ptr, UNUSED_WITHOUT_PTRAUTH const void *address) {
        if (!ptr)
            return nullptr;
        return ptrauth_auth_data(ptr, key, ptrauth_blend_discriminator(address, discriminator));
    }
};

// A template that produces a WrappedPtr to the given type using a
// plain unauthenticated pointer.
template <typename T> using RawPtr = WrappedPtr<T, PtrauthRaw>;

#if __has_feature(ptrauth_calls)
// Get a ptrauth type that uses a string discriminator.
#if __BUILDING_OBJCDT__
#define PTRAUTH_STR(name, ...) PtrauthStrip
#else
#define PTRAUTH_STR(name, ...) Ptrauth<ptrauth_string_discriminator(#name) __VA_OPT__(,) __VA_ARGS__>
#endif

// When ptrauth is available, declare a template that wraps a type
// in a WrappedPtr that uses an authenticated pointer using the
// process-dependent data key, address diversification, and a
// discriminator based on the name passed in.
//
// When ptrauth is not available, equivalent to RawPtr.
#define DECLARE_AUTHED_PTR_TEMPLATE(name)                      \
    template <typename T> using name ## _authed_ptr            \
        = WrappedPtr<T, PTRAUTH_STR(name)>;
#else
#define PTRAUTH_STR(name, ...) PtrauthRaw
#define DECLARE_AUTHED_PTR_TEMPLATE(name)                      \
    template <typename T> using name ## _authed_ptr = RawPtr<T>;
#endif

/// A global function pointer authenticated with address diversification which
/// supports atomic operations on the value. std::atomic does not play well with
/// `__ptrauth` so we do the operations manually.
template <typename Fn>
class PtrauthGlobalAtomicFunction {
#if __has_feature(ptrauth_calls)
    // We use the same discriminator for all PtrauthGlobalAtomicFunctions. Since
    // our scheme is address diversified, and these are always static objects,
    // there's no possibility that a signed function pointer in one of them will
    // be substitutable into another one.
    static constexpr ptrauth_extra_data_t discriminator = ptrauth_string_discriminator("PtrauthGlobalAtomicFunction");
#else
    static constexpr ptrauth_extra_data_t discriminator = 0;
#endif

    // Use atomicValue for almost all operations, but initialValue allows us to
    // have an initial value without needing a static initializer.
    union {
        std::atomic<void *> atomicValue;
        Fn __ptrauth(ptrauth_key_process_independent_code, 1, discriminator) initialValue;
    };

    Fn auth(void *signedValue) {
        if (!signedValue)
            return nullptr;
        return (Fn)ptrauth_auth_function(signedValue,
                                         ptrauth_key_process_independent_code,
                                         ptrauth_blend_discriminator(&atomicValue, discriminator));
    }

    void *sign(Fn fn) {
        if (!fn)
            return nullptr;
        return ptrauth_auth_and_resign((void *)fn,
                                       ptrauth_key_function_pointer, 0,
                                       ptrauth_key_function_pointer,
                                       ptrauth_blend_discriminator(&atomicValue, discriminator));
    }

public:
    constexpr PtrauthGlobalAtomicFunction(Fn f) : initialValue(f) {}

    bool isSet() {
        return atomicValue.load(std::memory_order_relaxed) != nullptr;
    }

    Fn load(std::memory_order order) {
        return auth(atomicValue.load(order));
    }

    void store(Fn value, std::memory_order order) {
        atomicValue.store(sign(value), order);
    }

    bool compare_exchange_weak(Fn &oldValue, Fn newValue, std::memory_order successOrder, std::memory_order failureOrder) {
        void *oldValueSigned = sign(oldValue);
        void *newValueSigned = sign(newValue);
        bool success = atomicValue.compare_exchange_weak(oldValueSigned, newValueSigned, successOrder, failureOrder);
        if (!success)
            oldValue = auth(oldValueSigned);
        return success;
    }
};

// These are used to protect the class_rx_t pointer enforcement flag
#if __has_feature(ptrauth_calls)
#define ptrauth_class_rx_enforce \
    __ptrauth_restricted_intptr(ptrauth_key_process_dependent_data, 1, 0x47f5)
#else
#define ptrauth_class_rx_enforce
#endif

// These protect various things in objc-block-trampolines.
#if __has_feature(ptrauth_calls)

#define ptrauth_trampoline_block_page_group \
    __ptrauth(ptrauth_key_process_dependent_data, 1, \
        ptrauth_string_discriminator("TrampolineBlockPageGroup"))
#define ptrauth_trampoline_textSegment \
    __ptrauth_restricted_intptr(ptrauth_key_process_dependent_data, 1, \
        ptrauth_string_discriminator("TrampolinePointerWrapper::TrampolinePointers::textSegment"))

#else

#define ptrauth_trampoline_block_page_group
#define ptrauth_trampoline_textSegment

#endif


// An enum for indicating whether to authenticate or strip. Use it as a template
// parameter for getters that usually need to authenticate but sometimes strip
// in very specific circumstances where that's not insecure.
enum class Authentication {
    Authenticate,
    Strip
};

// _OBJC_PTRAUTH_H_
#endif
