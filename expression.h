#ifndef __EXPRESSION_H__
#define __EXPRESSION_H__

#define EXPRESSION_ARGV_MAX (5)
struct expression {
	const char *operation;

	size_t argc;
	void *argv[EXPRESSION_ARGV_MAX];
};

#endif /*__EXPRESSION_H__*/
