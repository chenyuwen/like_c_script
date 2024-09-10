%{
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <limits.h>
#include <stdarg.h>
#include <errno.h>
#include "gnu_list.h"

#define YYDEBUG 1
int yydebug = 1;
int yylex();
void yyerror(char *s);

#define EXPRESSION_ARGV_MAX (5)
struct expression {
	const char *operation;

	size_t argc;
	void *argv[EXPRESSION_ARGV_MAX];
};
struct expression *root = NULL;

enum arith_express_type {
	AE_TYPE_INT,
	AE_TYPE_FLOAT,
};

struct arith_express_result {
	enum arith_express_type type;

	union {
		int intval;
		float floatval;
	};
};

struct variable {
	struct list_head list;
	const char *name;
	struct arith_express_result result;
};

struct variable_vector {
	struct list_head variable_lists;
	struct list_head list;
};

struct function {
	struct list_head list;
	struct list_head used;
	const char *name;
	struct expression *retval;
	struct expression *arguments;
	struct expression *express;

	size_t fargc;
	struct variable *fargv;
	struct arith_express_result result;

	struct list_head variable_vector_lists;
};

struct context {
	struct variable_vector variable_vector;
	struct list_head function_lists;

	struct list_head used_lists;
	int flag_returned;
};

struct expression *alloc_expression(const char *operation, const size_t argc, ...)
{
	struct expression *express = NULL;
	size_t i = 0;
	va_list args;

	express = malloc(sizeof(struct expression));
	if (express == NULL) {
		printf("%s: alloc memory failed.\n", __func__);
		return NULL;
	}
	memset(express, 0, sizeof(struct expression));

	printf("%s: \n", operation);
	va_start(args, argc);
	for (i = 0; i < argc; i++) {
		express->argv[i] = va_arg(args, void *);
	}
	va_end(args);

	express->operation = operation;
	return express;
}

int do_number(struct expression *express, struct arith_express_result *result)
{
	const char *num = express->argv[0];

	if (!strncmp(num, "0x", 2)) {
		result->intval = strtol(num, NULL, 16);
		return 0;
	}
	result->intval = strtol(num, NULL, 10);
	return 0;
}

struct variable *variable_find(struct context *ctx, const char *name)
{
	struct variable_vector *vector;
	struct variable *pos = NULL;
	struct function *func = NULL;
	size_t i = 0;

	if (!list_empty(&ctx->used_lists)) {
		func = list_first_entry(&ctx->used_lists, struct function, used);

		list_for_each_entry(vector, &func->variable_vector_lists, list) {
			list_for_each_entry(pos, &vector->variable_lists, list) {
				if (!strcmp(pos->name, name)) {
					return pos;
				}
			}
		}

		for (i = 0; i < func->fargc; i++) {
			pos = &(func->fargv[i]);
			if (!strcmp(pos->name, name)) {
				return pos;
			}
		}
	}

	vector = &ctx->variable_vector;
	list_for_each_entry(pos, &vector->variable_lists, list) {
		if (!strcmp(pos->name, name)) {
			return pos;
		}
	}

	return NULL;
}

struct variable_vector *current_variable_vector(struct context *ctx)
{
	struct function *func = NULL;
	struct variable_vector *vector = NULL;

	if (list_empty(&ctx->used_lists)) {
		return &ctx->variable_vector;
	}

	func = list_first_entry(&ctx->used_lists, struct function, used);
	vector = list_first_entry(&func->variable_vector_lists,
		struct variable_vector, list);
	return vector;
}

int do_call_function(struct context *ctx, const char *fname,
	struct arith_express_result *results, const size_t result_size,
	struct arith_express_result *result);

int do_arithmetic_expression(struct context *ctx, struct expression *express,
	struct arith_express_result *result);

int do_call_with_expression(struct context *ctx, struct expression *express,
	struct arith_express_result *result)
{
	struct expression *next = NULL;
	const char *fname = express->argv[0];
	struct arith_express_result *fargv = NULL;
	size_t argc = 0, i = 0;
	int ret = 0;

	for (next = express->argv[1]; next != NULL; next = next->argv[1]) {
		argc++;
	}

	printf("%s %s size: %lu\n", __func__, express->operation, argc);
	fargv = malloc(sizeof(struct arith_express_result) * argc);
	if (fargv == NULL) {
		return -ENOMEM;
	}

	for (next = express->argv[1]; next != NULL; next = next->argv[1]) {
		struct arith_express_result *tmp = &fargv[i++];

		printf("%s %s\n", __func__, next->operation);
		ret = do_arithmetic_expression(ctx, next->argv[0], tmp);
		if (ret < 0) {
			free(fargv);
			return ret;
		}
	}

	ret = do_call_function(ctx, fname, fargv, argc, result);
	free(fargv);
	return ret;
}

int do_arithmetic_expression(struct context *ctx, struct expression *express,
	struct arith_express_result *result)
{
	struct arith_express_result result1, result2;
	int ret = 0;

	if (!strcmp(express->operation, "abs")) {
		ret = do_arithmetic_expression(ctx, express->argv[0], result);
		if (ret < 0) {
			return ret;
		}

		if (result->intval < 0) {
			result->intval = -result->intval;
		}
		return 0;
	} else if (!strcmp(express->operation, "(")) {
		return do_arithmetic_expression(ctx, express->argv[0], result);
	} else if (!strcmp(express->operation, "invert")) {
		result1 = *result;
		ret = do_arithmetic_expression(ctx, express->argv[0], &result1);
		if (ret < 0) {
			return ret;
		}
		result->intval = -result1.intval; /*TODO*/
		return 0;
	} else if (!strcmp(express->operation, "number")) {
		return do_number(express, result);
	} else if (!strcmp(express->operation, "symbol")) {
		struct variable *var = NULL;
		var = variable_find(ctx, express->argv[0]);
		if (var == NULL) {
			return -EINVAL;
		}

		*result = var->result;
		return 0;
	} else if (!strcmp(express->operation, "call")) {
		ret = do_call_with_expression(ctx, express, &result1);

		*result = result1;
		return ret;
	}

	result1 = *result;
	ret = do_arithmetic_expression(ctx, express->argv[0], &result1);
	if (ret < 0) {
		return ret;
	}

	result2 = *result;
	ret = do_arithmetic_expression(ctx, express->argv[1], &result2);
	if (ret < 0) {
		return ret;
	}

	if (!strcmp(express->operation, "+")) {
		result->intval = result1.intval + result2.intval;
		return 0;
	} else if (!strcmp(express->operation, "-")) {
		result->intval = result1.intval - result2.intval;
		return 0;
	} else if (!strcmp(express->operation, "*")) {
		result->intval = result1.intval * result2.intval;
		return 0;
	} else if (!strcmp(express->operation, "/")) {
		result->intval = result1.intval * result2.intval;
		return 0;
	} else if (!strcmp(express->operation, "&")) {
		result->intval = result1.intval & result2.intval;
		return 0;
	} else if (!strcmp(express->operation, "&")) {
		result->intval = result1.intval & result2.intval;
		return 0;
	}
	return 0;
}

int do_data_type(struct expression *express, enum arith_express_type *type)
{
	const char *data_type = express->argv[0];

	printf("OK %s: %s\n", express->operation, data_type);
	if (!strcmp(data_type, "int")) {
		return AE_TYPE_INT;
	} else if (!strcmp(data_type, "float")) {
		return AE_TYPE_FLOAT;
	}
	return 0;
}

int do_declare_variable(struct context *ctx, struct expression *express)
{
	enum arith_express_type type;
	struct expression *next = NULL;
	struct variable *var = NULL;
	int ret = 0;

	ret = do_data_type(express->argv[0], &type);
	if (ret < 0) {
		return ret;
	}

	for (next = express->argv[1]; next != NULL; next = next->argv[1]) {
		struct expression *var_exp = next->argv[0];

		var = malloc(sizeof(struct variable));
		if (var == NULL) {
			return -ENOMEM;
		}

		var->name = var_exp->argv[0];
		var->result.type = type;
		var->result.intval = 0;
		if (var_exp->argv[1] != NULL) {
			ret = do_arithmetic_expression(ctx, var_exp->argv[1],
				&var->result);
			if (ret < 0) {
				free(var);
				return ret;
			}
		}
		list_add(&var->list, &current_variable_vector(ctx)->variable_lists);
		printf("%s = %d\n", (const char *)var->name, var->result.intval);
	}
	return 0;
}

int do_declare_function(struct context *ctx, struct expression *express)
{
	struct function *func = NULL;
	struct expression *next = NULL;
	int i = 0, ret = 0;

	func = malloc(sizeof(struct function));
	if (func == NULL) {
		return -ENOMEM;
	}
	func->arguments = express->argv[2];
	func->fargc = 0;
	for (next = express->argv[2]; next != NULL; next = next->argv[2]) {
		printf("kk");
		func->fargc++;
	}

	func->fargv = malloc(sizeof(struct variable) * func->fargc);
	if (func->fargv == NULL) {
		free(func);
		return -ENOMEM;
	}

	for (next = express->argv[2]; next != NULL; next = next->argv[2]) {
		struct variable *var = &(func->fargv[i++]);

		ret = do_data_type(next->argv[0], &var->result.type);
		if (ret < 0) {
			free(func->fargv);
			free(func);
			return ret;
		}
		var->name = next->argv[1];
		printf("argument: %s\n", var->name);
	}

	func->name = express->argv[1];
	func->retval = express->argv[0];
	func->express = express->argv[3];
	list_add(&func->list, &ctx->function_lists);
	printf("FUNC name %s: \n", (const char *)express->argv[1]);
	return 0;
}

int do_declare_variable_and_function(struct context *ctx, struct expression *express)
{
	struct expression *next = NULL;
	printf("KK%s: \n", express->operation);

	if (strcmp(express->operation, "declare_variable_and_function")) {
		return -1;
	}
	next = express->argv[0];

	if (!strcmp(next->operation, "declare_function")) {
		return do_declare_function(ctx, next);
	} else if (!strcmp(next->operation, "declare_variable")) {
		return do_declare_variable(ctx, next);
	}
	return 0;
}

int pretreat_root(struct context *ctx, struct expression *express)
{
	struct expression *next = NULL;
	int ret = 0;

	if (express == NULL) {
		return 0;
	}

	for (next = express->argv[0]; next != NULL; next = next->argv[1]) {
		printf("%s: \n", next->operation);

		ret = do_declare_variable_and_function(ctx, next->argv[0]);
		if (ret < 0) {
			return ret;
		}
	}
	return 0;
}

int __do_symbol_equal(struct context *ctx, struct expression *express)
{
	struct variable *var = NULL;
	struct arith_express_result result;
	const char *varname = express->argv[0];
	int ret = 0;

	var = variable_find(ctx, varname);
	if (var == NULL) {
		return -EINVAL;
	}

	ret = do_arithmetic_expression(ctx, express->argv[1], &var->result);
	if (ret < 0) {
		return ret;
	}
	printf("varname: %s = %d\n", varname, var->result.intval);
	return 0;
}

int do_expressions(struct context *ctx, struct expression *express);

int do_logical_expression(struct context *ctx, struct expression *express)
{
	int ret = 0;

	printf("do %s\n", express->operation);
	if (!strcmp(express->operation, "declare_variable")) {
		return do_declare_variable(ctx, express->argv[0]);
	} else if (!strcmp(express->operation, "expression")) {
		struct arith_express_result result;

		ret = do_arithmetic_expression(ctx, express->argv[0], &result);
		if (ret < 0) {
			return ret;
		}
		return 0;
	} else if (!strcmp(express->operation, "=")) {
		return __do_symbol_equal(ctx, express);
	} else if (!strcmp(express->operation, "while")) {
		struct arith_express_result result;

		do {
			ret = do_arithmetic_expression(ctx, express->argv[0], &result);
			if (ret < 0 || result.intval == 0) {
				return ret;
			}

			ret = do_expressions(ctx, express->argv[1]);
			if (ret < 0) {
				return ret;
			}
		} while (!ctx->flag_returned);
		return 0;
	} else if (!strcmp(express->operation, "if")) {
		struct arith_express_result result;

		ret = do_arithmetic_expression(ctx, express->argv[0], &result);
		if (ret < 0) {
			return ret;
		}

		if (result.intval != 0) {
			return do_expressions(ctx, express->argv[1]);
		}
		return 0;
	} else if (!strcmp(express->operation, "return")) {
		struct arith_express_result result;
		struct function *func = NULL;

		ret = do_arithmetic_expression(ctx, express->argv[0], &result);
		if (ret < 0) {
			return ret;
		}

		ctx->flag_returned = 1;
		func = list_first_entry(&ctx->used_lists, struct function, used);
		if (func == NULL) {
			return -EINVAL;
		}
		func->result = result;
		printf("return OK %d\n", result.intval);
		return 0;
	}
	return 0;
}

int do_expressions(struct context *ctx, struct expression *express)
{
	struct expression *next = NULL;
	int ret = 0;

	if (express == NULL) {
		return 0;
	}

	for (next = express; next != NULL; next = next->argv[1]) {
		ret = do_logical_expression(ctx, next->argv[0]);
		if (ret < 0) {
			return ret;
		}

		if (ctx->flag_returned) {
			break;
		}
	}
	return 0;
}

int do_call_function(struct context *ctx, const char *fname,
	struct arith_express_result *results, const size_t result_size,
	struct arith_express_result *result)
{
	struct function *pos = NULL, *func = NULL;
	struct variable_vector vector;
	int ret = 0;
	size_t i = 0;

	list_for_each_entry(pos, &ctx->function_lists, list) {
		if (!strcmp(pos->name, fname)) {
			func = pos;
			break;
		}
	}
	if (func == NULL) {
		return -EINVAL;
	}

	for (i = 0; i < func->fargc && i < result_size; i++) {
		struct variable *variable = &func->fargv[i];

		variable->result.intval = results[i].intval;
	}

	INIT_LIST_HEAD(&vector.variable_lists);
	INIT_LIST_HEAD(&func->variable_vector_lists);
	list_add_tail(&vector.list, &func->variable_vector_lists);

	list_add(&func->used, &ctx->used_lists);
	ctx->flag_returned = 0;
	ret = do_expressions(ctx, func->express);
	*result = func->result;
	ctx->flag_returned = 0;
	list_del(&func->used);
	list_del(&vector.list);
	return ret;
}

%}

%union {
	struct expression *express;
	char *strval;
	int intval;
}

/*declare tokens */

%token <strval> NUMBER
%token <strval> SYMBOL

%left '+' '-'
%left '*' '/'
%left '&'
%nonassoc '(' ')' '|'
%right '%'
%left CMP
%left '='
%left ';'
%nonassoc '{' '}'

%type <express> arithmetic_expression arguments expressions one_exp
%type <express> declare_variable_and_function declare_variable_and_functions
%type <express> data_type declare_function
%type <express> variable_symbol variable_symbols
%type <express> function_arguments declare_variable
%type <express> root
%token <intval> CMP
%token IF WHILE RETURN
%token DATA_TYPE_INT DATA_TYPE_FLOAT DATA_TYPE_VOLD DATA_TYPE_STRUCT

%%

root:
	  declare_variable_and_functions { $$ = alloc_expression("root", 1, $1); root = $$; }
	;

declare_variable_and_functions:
	  declare_variable_and_function { $$ = alloc_expression("declare_variable_and_functions", 2, $1, NULL); }
	| declare_variable_and_function declare_variable_and_functions { $$ = alloc_expression("declare_variable_and_functions", 2, $1, $2); }
	;

declare_variable_and_function:
	  declare_variable ';' { $$ = alloc_expression("declare_variable_and_function", 1, $1); }
	| declare_function { $$ = alloc_expression("declare_variable_and_function", 1, $1); }
	;

declare_variable:
	  data_type variable_symbols { $$ = alloc_expression("declare_variable", 2, $1, $2); }
	;

variable_symbols:
	  variable_symbol { $$= alloc_expression("variable_symbols", 2, $1, NULL); }
	| variable_symbol ',' variable_symbols { $$= alloc_expression("variable_symbols", 2, $1, $3); }
	;

variable_symbol:
	  SYMBOL { $$= alloc_expression("variable_symbol", 1, $1); }
	| SYMBOL '=' arithmetic_expression { $$= alloc_expression("variable_symbol", 2, $1, $3); }
	;

data_type:
	  DATA_TYPE_INT { $$= alloc_expression("data_type", 1, "int"); }
	| DATA_TYPE_FLOAT{ $$= alloc_expression("data_type", 1, "float"); }
	| DATA_TYPE_VOLD { $$= alloc_expression("data_type", 1, "vold"); }
	| DATA_TYPE_STRUCT SYMBOL { $$= alloc_expression("data_type", 2, "struct", $2); }
	;

declare_function:
	  data_type SYMBOL '(' function_arguments ')' '{' '}' { $$ = alloc_expression("declare_function", 4, $1, $2, $4, NULL); }
	| data_type SYMBOL '(' function_arguments ')' '{' expressions '}' { $$ = alloc_expression("declare_function", 4, $1, $2, $4, $7); }
	;

function_arguments:
	  { $$ = NULL; }
	| data_type SYMBOL { $$ = alloc_expression("function_arguments", 3, $1, $2, NULL); }
	| data_type SYMBOL ',' function_arguments { $$ = alloc_expression("function_arguments", 3, $1, $2, $4); }
	;

expressions:
	  one_exp { $$ = alloc_expression("expressions", 1, $1); }
	| one_exp expressions { $$ = alloc_expression("expressions", 2, $1, $2); }
	;

one_exp:
	  arithmetic_expression ';' { $$ = alloc_expression("expression", 1, $1); }
	| declare_variable ';' { $$ = alloc_expression("declare_variable", 1, $1); }
	| SYMBOL '=' arithmetic_expression ';' { $$ = alloc_expression("=", 2, $1, $3); }
	| RETURN arithmetic_expression ';' { $$ = alloc_expression("return", 1, $2); }
	| WHILE '(' arithmetic_expression ')' '{' expressions '}' { $$ = alloc_expression("while", 2, $3, $6);}
	| WHILE '(' arithmetic_expression ')' '{' '}' { $$ = alloc_expression("while", 2, $3, NULL); }
	| IF '(' arithmetic_expression ')' '{' expressions '}' { $$ = alloc_expression("if", 2, $3, $6); }
	| IF '(' arithmetic_expression ')' '{' '}' { $$ = alloc_expression("if", 2, $3, NULL); }
	;

arithmetic_expression:
          arithmetic_expression '+' arithmetic_expression { $$ = alloc_expression("+", 2, $1, $3); }
	| arithmetic_expression '-' arithmetic_expression { $$ = alloc_expression("-", 2, $1, $3); }
	| arithmetic_expression '*' arithmetic_expression { $$ = alloc_expression("*", 2, $1, $3); }
	| arithmetic_expression '/' arithmetic_expression { $$ = alloc_expression("/", 2, $1, $3); }
	| arithmetic_expression '&' arithmetic_expression { $$ = alloc_expression("&", 2, $1, $3); }
	| arithmetic_expression '|' arithmetic_expression { $$ = alloc_expression("|", 2, $1, $3); }
	| '|' arithmetic_expression '|' { $$ = alloc_expression("abs", 1, $2); }
	| '(' arithmetic_expression ')' { $$ = alloc_expression("(", 1, $2); }
	| '-' arithmetic_expression     { $$ = alloc_expression("invert", 1, $2); }
	| NUMBER      { $$ = alloc_expression("number", 1, $1); }
	| SYMBOL      { $$ = alloc_expression("symbol", 1, $1); }
	| SYMBOL '(' arguments ')' { $$ = alloc_expression("call", 2, $1, $3); }
	;

arguments:
	  { $$ = NULL; }
	| arithmetic_expression { $$ = alloc_expression("arguments", 2, $1, NULL); }
	| arithmetic_expression ',' arguments { $$ = alloc_expression("arguments", 2, $1, $3); }
	;
%%

int main(int argc, char ** argv)
{
	struct context ctx = {0};
	struct arith_express_result result;
	int ret = 0;

	yyparse();

	INIT_LIST_HEAD(&ctx.variable_vector.variable_lists);
	INIT_LIST_HEAD(&ctx.function_lists);
	INIT_LIST_HEAD(&ctx.used_lists);

	ret = pretreat_root(&ctx, root);
	if (ret < 0) {
		return ret;
	}

	return do_call_function(&ctx, "main", NULL, 0, &result);
}

void yyerror(char *s)
{
	fprintf(stderr, "error:%s\n", s);
}
