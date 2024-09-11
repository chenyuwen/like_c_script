#ifndef __EXPRESSION_H__
#define __EXPRESSION_H__

#include <limits.h>

#define EXPRESSION_ARGV_MAX (5)
struct expression {
	const char *operation;

	size_t argc;
	void *argv[EXPRESSION_ARGV_MAX];
};

#define TO_EXPRESS(string) (char *)((unsigned long)(string) | 0x1)
#define TO_STRING(express) (char *)((unsigned long)(express) & (ULONG_MAX - 1))
#define IS_STRING(express) (((unsigned long)express) & 0x1)

#endif /*__EXPRESSION_H__*/
