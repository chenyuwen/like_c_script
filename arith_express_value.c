#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <stdlib.h>

#include "expression.h"
#include "arith_express_value.h"

int atith_express_value_init(struct arith_express_value *value,
	struct expression *express)
{
	const char *data_type = NULL;

	if (express == NULL) {
		value->type = AE_TYPE_INT;
		value->intval = 0;
		return 0;
	}

	data_type = express->argv[0];
	if (!strcmp(data_type, "int")) {
		value->type = AE_TYPE_INT;
		value->intval = 0;
	} else if (!strcmp(data_type, "float")) {
		value->type = AE_TYPE_FLOAT;
		value->floatval = 0;
	} else if (!strcmp(data_type, "char")) {
		value->type = AE_TYPE_CHAR;
		value->charval = 0;
	} else if (!strcmp(data_type, "vold")) {
		value->type = AE_TYPE_VOLD;
	} else {
		printf("Error %s: %d\n", __func__, __LINE__);
	}
	return 0;
}

int atith_express_value_init_by_num(struct arith_express_value *value,
	const char *number)
{
	int is_float = !!strchr(number, '.');

	if (is_float) {
		value->type = AE_TYPE_FLOAT;
		value->floatval = strtof(number, NULL);
		return 0;
	}

	value->type = AE_TYPE_INT;
	if (!strncmp(number, "0x", 2)) {
		value->intval = strtol(number, NULL, 16);
		return 0;
	}
	value->intval = strtol(number, NULL, 10);
	return 0;
}

#define ARITH_EXPRESS_VALUE_TO(__type) \
static __type arith_express_value_to_##__type(struct arith_express_value *value) \
{ \
	switch (value->type) { \
	case AE_TYPE_INT: \
		return value->intval; \
	case AE_TYPE_FLOAT: \
		return value->floatval; \
	case AE_TYPE_CHAR: \
		return value->charval; \
	} \
	printf("Error %s: %d\n", __func__, __LINE__); \
	return 0; \
}
ARITH_EXPRESS_VALUE_TO(int);
ARITH_EXPRESS_VALUE_TO(float);
ARITH_EXPRESS_VALUE_TO(char);

#define ARITH_EXPRESE_VALUE_CALCULATE2(__type, __valuename) \
static int arith_express_value_calculate2_##__type(struct arith_express_value *result, \
	const int opt, struct arith_express_value *value) \
{ \
	switch (opt) { \
	case '+': \
		result->__valuename += arith_express_value_to_##__type(value); \
		break; \
	case '-': \
		result->__valuename -= arith_express_value_to_##__type(value); \
		break; \
	case '*': \
		result->__valuename *= arith_express_value_to_##__type(value); \
		break; \
	case '/': \
		result->__valuename /= arith_express_value_to_##__type(value); \
		break; \
	case '&': \
		result->__valuename &= arith_express_value_to_##__type(value); \
		break; \
	case '|': \
		result->__valuename |= arith_express_value_to_##__type(value); \
		break; \
	case CAL2_OPT_EQUAL: \
		result->__valuename = (result->__valuename == value->__valuename); \
		break; \
	case CAL2_OPT_NOT_EQUAL: \
		result->__valuename = (result->__valuename != value->__valuename); \
		break; \
	case CAL2_OPT_LESS: \
		result->__valuename = (result->__valuename < value->__valuename); \
		break; \
	case CAL2_OPT_LESS_EQUAL: \
		result->__valuename = (result->__valuename <= value->__valuename); \
		break; \
	case CAL2_OPT_GREAT: \
		result->__valuename = (result->__valuename > value->__valuename); \
		break; \
	case CAL2_OPT_GREAT_EQUAL: \
		result->__valuename = (result->__valuename >= value->__valuename); \
		break; \
	default: \
		printf("Error %s: %d\n", __func__, __LINE__); \
		return -EINVAL; \
	} \
	return 0; \
}
ARITH_EXPRESE_VALUE_CALCULATE2(int, intval);
ARITH_EXPRESE_VALUE_CALCULATE2(char, charval);

static int arith_express_value_calculate2_float(struct arith_express_value *result,
	const int opt, struct arith_express_value *value)
{
	switch (opt) {
	case '+':
		result->floatval += arith_express_value_to_float(value);
		break;
	case '-':
		result->floatval -= arith_express_value_to_float(value);
		break;
	case '*':
		result->floatval *= arith_express_value_to_float(value);
		break;
	case '/':
		result->floatval /= arith_express_value_to_float(value);
		break;
	default:
		printf("Error %s: %d\n", __func__, __LINE__);
		return -EINVAL;
	}
	return 0;
}

int arith_express_value_calculate2(struct arith_express_value *result, const int opt,
	struct arith_express_value *value)
{
	switch (result->type) {
	case AE_TYPE_INT:
		return arith_express_value_calculate2_int(result, opt, value);
	case AE_TYPE_FLOAT:
		return arith_express_value_calculate2_float(result, opt, value);
	case AE_TYPE_CHAR:
		return arith_express_value_calculate2_char(result, opt, value);
	}
	printf("Error %s: %d\n", __func__, __LINE__);
	return -EINVAL;
}

#define ARITH_EXPRESS_VALUE_CALCULATE1(__type, __valuename) \
static int arith_express_value_calculate1_##__type(struct arith_express_value *value, \
	const enum cal1_opt opt) \
{ \
	switch (opt) { \
	case CAL1_OPT_INVERT: \
		value->__valuename = -(value->__valuename); \
		break; \
	case CAL1_OPT_ABS: \
		if (value->__valuename < 0) { \
			value->__valuename = -(value->__valuename); \
		} \
		break; \
	default: \
		printf("Error %s: %d\n", __func__, __LINE__); \
		return -EINVAL; \
	} \
	return 0; \
}
ARITH_EXPRESS_VALUE_CALCULATE1(int, intval);
ARITH_EXPRESS_VALUE_CALCULATE1(float, floatval);
ARITH_EXPRESS_VALUE_CALCULATE1(char, charval);

int arith_express_value_calculate1(struct arith_express_value *value,
	const enum cal1_opt opt)
{
	switch (value->type) {
	case AE_TYPE_INT:
		return arith_express_value_calculate1_int(value, opt);
	case AE_TYPE_FLOAT:
		return arith_express_value_calculate1_float(value, opt);
	case AE_TYPE_CHAR:
		return arith_express_value_calculate1_char(value, opt);
	}
	printf("Error %s: %d\n", __func__, __LINE__);
	return -EINVAL;
}

int arith_express_value_convert(struct arith_express_value *dest,
	struct arith_express_value *src)
{
	switch (dest->type) {
	case AE_TYPE_INT:
		dest->intval = arith_express_value_to_int(src);
		break;
	case AE_TYPE_FLOAT:
		dest->floatval = arith_express_value_to_float(src);
		break;
	case AE_TYPE_CHAR:
		dest->charval = arith_express_value_to_char(src);
		break;
	case AE_TYPE_VOLD:
		dest->intval = 0;
		break;
	default:
		printf("Error %s: %d\n", __func__, __LINE__);
		return -EINVAL;
	}
	return 0;
}
