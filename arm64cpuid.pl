#! /usr/bin/env perl
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Copyright 2015-2020 The OpenSSL Project Authors. All Rights Reserved.

# Modifications are copyright Amazon. Any included source code is
# copyrighted by the OpenSSL project and its contributors.

# Some parts of this file have been sourced from openssl/crypto/arm64cpuid.pl

# $output is the last argument if it looks like a file (it has an extension)
# $flavour is the first argument if it doesn't look like a file
$output = $#ARGV >= 0 && $ARGV[$#ARGV] =~ m|\.\w+$| ? pop : undef;
$flavour = $#ARGV >= 0 && $ARGV[0] !~ m|\.| ? shift : undef;

$0 =~ m/(.*[\/\\])[^\/\\]+$/; $dir=$1;
( $xlate="${dir}arm-xlate.pl" and -f $xlate ) or
( $xlate="${dir}perlasm/arm-xlate.pl" and -f $xlate) or
die "can't locate arm-xlate.pl";

open OUT,"| \"$^X\" $xlate $flavour \"$output\""
    or die "can't call $xlate: $!";
*STDOUT=*OUT;

$code.=<<___;
.globl	_armv8_rng_probe
.type	_armv8_rng_probe,%function
_armv8_rng_probe:
	mrs	x0, s3_3_c2_c4_0	// rndr
	mrs	x0, s3_3_c2_c4_1	// rndrrs
	ret
.size	_armv8_rng_probe,.-_armv8_rng_probe
___

sub gen_random {
my $rdop = shift;
my $rand_reg = $rdop eq "rndr" ? "s3_3_c2_c4_0" : "s3_3_c2_c4_1";

print<<___;
// Fill buffer with Randomly Generated Bytes
// inputs:  char * in x0 - Pointer to buffer
//          size_t in x1 - Number of bytes to write to buffer
// outputs: size_t in x0 - Number of bytes successfully written to buffer
.globl	OPENSSL_${rdop}_asm
.type	OPENSSL_${rdop}_asm,%function
.align	4
OPENSSL_${rdop}_asm:
	mov	x2,xzr		//reg for bytes stored successfully
	mov	x3,xzr		//reg for storing ${rdop}

.align	4
.Loop_${rdop}:
	cmp	x1,#0		//bytes left to write to buffer comparison to 0
	b.eq	.${rdop}_done	//branch if 0 bytes are left to write to buffer
	mov	x3,xzr
	mrs	x3,$rand_reg	//copy ${rdop}'s value into x3
	b.eq	.${rdop}_done	//branch if failed (Z=1)

	cmp	x1,#8
	b.lt	.Loop_single_byte_${rdop} //if less than 8 bytes are left to be copied branch

	str	x3,[x0]		//store ${rdop}'s result at buffer's mem location
	add	x0,x0,#8	//add 8 bytes to buffers location
	add	x2,x2,#8	//add 8 bytes to bytes_successfully_stored
	subs	x1,x1,#8	//subtract 8 from bytes left
	b.ge	.Loop_${rdop}	//if bytes left is gte to 8, branch

.align	4
.Loop_single_byte_${rdop}:
	strb	w3,[x0]		//store least sig byte from ${rdop}'s result to buffer's mem location
	lsr	x3,x3,#8	//move next byte (8 bits) into lsb so each byte remains random
	add	x2,x2,#1	//add 1 byte to bytes successfully_stored
	add	x0,x0,#1	//add 1 byte to buffer's mem location
	subs	x1,x1,#1	//subtract 1 from bytes left
	b.gt	.Loop_single_byte_${rdop}

.align	4
.${rdop}_done:
	mov	x0,x2		//return number of bytes successfully stored
	ret
.size	OPENSSL_${rdop}_asm,.-OPENSSL_${rdop}_asm
___
}
gen_random("rndr");
gen_random("rndrrs");

print $code;
close STDOUT or die "error closing STDOUT: $!";