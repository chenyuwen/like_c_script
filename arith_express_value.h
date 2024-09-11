#ifndef __ARITH_EXPRESS_VALUE_H__
#define __ARITH_EXPRESS_VALUE_H__

enum arith_express_type {
	AE_TYPE_INT,
	AE_TYPE_FLOAT,
	AE_TYPE_CHAR,
	AE_TYPE_VOLD,
	AE_TYPE_NOT_SET,
};

struct arith_express_value {
	enum arith_express_type type;

	union {
		int intval;
		float floatval;
		char charval;
	};
};

int arith_express_value_init(struct arith_express_value *value,
	struct expression *express);

int arith_express_value_init_by_num(struct arith_express_value *value,
	const char *number);

#define CAL2_OPT_EQUAL 1000
#define CAL2_OPT_NOT_EQUAL 1001
#define CAL2_OPT_LESS_EQUAL 1002
#define CAL2_OPT_LESS 1003
#define CAL2_OPT_GREAT_EQUAL 1004
#define CAL2_OPT_GREAT 1005

int arith_express_value_calculate2(struct arith_express_value *result, const int opt,
	struct arith_express_value *value);

enum cal1_opt {
	CAL1_OPT_INVERT = 1,
	CAL1_OPT_ABS,
};

int arith_express_value_calculate1(struct arith_express_value *value,
	const enum cal1_opt opt);

int arith_express_value_convert(struct arith_express_value *dest,
	struct arith_express_value *src);

void arith_express_value_print(const char *name, struct arith_express_value *value);

int arith_express_value_equal(struct arith_express_value *value, int intval);

#endif /*__ARITH_EXPRESS_VALUE_H__*/
