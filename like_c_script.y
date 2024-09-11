%{
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <limits.h>
#include <stdarg.h>
#include <errno.h>

#include "expression.h"
#include "arith_express_value.h"
#include "gnu_list.h"

//#define YYDEBUG 1
//int yydebug = 1;
int yylex();
void yyerror(char *s);

struct expression *root = NULL;

struct variable {
	struct list_head list;
	const char *name;
	struct arith_express_value value;
};

struct variable_vector {
	struct list_head variable_lists;
	struct list_head list;
};

struct function {
	struct list_head list;
	const char *name;
	struct expression *retval;
	struct expression *arguments;
	struct expression *express;

	size_t fargc;
	struct variable *fargv;
	struct arith_express_value freturn_value;
};

struct function_runtime {
	struct list_head list;
	struct function *func;
	struct arith_express_value return_value;

	struct variable_vector default_vector;
	struct list_head variable_vector_lists;

	size_t argc;
	struct variable argv[1];
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

	va_start(args, argc);
	for (i = 0; i < argc; i++) {
		express->argv[i] = va_arg(args, void *);
	}
	va_end(args);

	express->operation = operation;
	return express;
}

int do_number(struct expression *express, struct arith_express_value *result)
{
	const char *num = express->argv[0];

	return arith_express_value_init_by_num(result, num);
}

struct variable *variable_find(struct context *ctx, const char *name)
{
	struct variable_vector *vector;
	struct variable *pos = NULL;
	struct function_runtime *runtime = NULL;
	size_t i = 0;

	if (!list_empty(&ctx->used_lists)) {
		runtime = list_first_entry(&ctx->used_lists,
			struct function_runtime, list);

		list_for_each_entry(vector, &runtime->variable_vector_lists, list) {
			list_for_each_entry(pos, &vector->variable_lists, list) {
				if (!strcmp(pos->name, name)) {
					return pos;
				}
			}
		}

		for (i = 0; i < runtime->argc; i++) {
			pos = &(runtime->argv[i]);
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
	struct function_runtime *runtime = NULL;
	struct variable_vector *vector = NULL;

	if (list_empty(&ctx->used_lists)) {
		return &ctx->variable_vector;
	}

	runtime = list_first_entry(&ctx->used_lists, struct function_runtime, list);
	vector = list_first_entry(&runtime->variable_vector_lists,
		struct variable_vector, list);
	return vector;
}

int do_call_function(struct context *ctx, const char *fname,
	struct arith_express_value *results, const size_t result_size,
	struct arith_express_value *result);

int do_arithmetic_expression(struct context *ctx, struct expression *express,
	struct arith_express_value *result);

int do_call_with_expression(struct context *ctx, struct expression *express,
	struct arith_express_value *result)
{
	struct expression *next = NULL;
	const char *fname = express->argv[0];
	struct arith_express_value *argv = NULL;
	size_t argc = 0, i = 0;
	int ret = 0;

	for (next = express->argv[1]; next != NULL; next = next->argv[1]) {
		argc++;
	}

	argv = malloc(sizeof(struct arith_express_value) * argc);
	if (argv == NULL) {
		return -ENOMEM;
	}

	for (next = express->argv[1]; next != NULL; next = next->argv[1]) {
		struct arith_express_value *tmp = &argv[i++];

		arith_express_value_init(tmp, NULL);
		ret = do_arithmetic_expression(ctx, next->argv[0], tmp);
		if (ret < 0) {
			free(argv);
			return ret;
		}
	}

	ret = do_call_function(ctx, fname, argv, argc, result);
	free(argv);
	return ret;
}

int do_cmp_expression(struct context *ctx, struct expression *express,
	struct arith_express_value *result)
{
	int ret = 0;
	struct arith_express_value arg1, arg2;
	const char *cmp = express->argv[1];

	arith_express_value_init(&arg1, NULL);
	arith_express_value_init(&arg2, NULL);

	ret = do_arithmetic_expression(ctx, express->argv[0], &arg1);
	if (ret < 0) {
		return ret;
	}

	ret = do_arithmetic_expression(ctx, express->argv[2], &arg2);
	if (ret < 0) {
		return ret;
	}

	if (!strcmp(cmp, "!=")) {
		ret = arith_express_value_calculate2(&arg1, CAL2_OPT_NOT_EQUAL, &arg2);
	} else if (!strcmp(cmp, "==")) {
		ret = arith_express_value_calculate2(&arg1, CAL2_OPT_EQUAL, &arg2);
	} else if (!strcmp(cmp, "<")) {
		ret = arith_express_value_calculate2(&arg1, CAL2_OPT_LESS, &arg2);
	} else if (!strcmp(cmp, ">")) {
		ret = arith_express_value_calculate2(&arg1, CAL2_OPT_GREAT, &arg2);
	} else if (!strcmp(cmp, ">=")) {
		ret = arith_express_value_calculate2(&arg1, CAL2_OPT_GREAT_EQUAL, &arg2);
	} else if (!strcmp(cmp, "<=")) {
		ret = arith_express_value_calculate2(&arg1, CAL2_OPT_LESS_EQUAL, &arg2);
	}

	return arith_express_value_convert(result, &arg1);
}

int do_arithmetic_expression(struct context *ctx, struct expression *express,
	struct arith_express_value *result)
{
	struct arith_express_value arg1, arg2;
	int ret = 0;

	arith_express_value_init(&arg1, NULL);
	arith_express_value_init(&arg2, NULL);

	if (!strcmp(express->operation, "abs")) {
		ret = do_arithmetic_expression(ctx, express->argv[0], result);
		if (ret < 0) {
			return ret;
		}
		return arith_express_value_calculate1(result, CAL1_OPT_ABS);
	} else if (!strcmp(express->operation, "(")) {
		return do_arithmetic_expression(ctx, express->argv[0], result);
	} else if (!strcmp(express->operation, "invert")) {
		ret = do_arithmetic_expression(ctx, express->argv[0], result);
		if (ret < 0) {
			return ret;
		}
		return arith_express_value_calculate1(result, CAL1_OPT_INVERT);
	} else if (!strcmp(express->operation, "number")) {
		return do_number(express, result);
	} else if (!strcmp(express->operation, "symbol")) {
		struct variable *var = NULL;

		var = variable_find(ctx, express->argv[0]);
		if (var == NULL) {
			return -EINVAL;
		}
		return arith_express_value_convert(result, &var->value);
	} else if (!strcmp(express->operation, "call")) {
		ret = do_call_with_expression(ctx, express, &arg1);
		return arith_express_value_convert(result, &arg1);
	} else if (!strcmp(express->operation, "cmp")) {
		return do_cmp_expression(ctx, express, result);
	}

	ret = do_arithmetic_expression(ctx, express->argv[0], &arg1);
	if (ret < 0) {
		return ret;
	}

	ret = do_arithmetic_expression(ctx, express->argv[1], &arg2);
	if (ret < 0) {
		return ret;
	}

	ret = arith_express_value_calculate2(&arg1, express->operation[0], &arg2);
	if (ret < 0) {
		return ret;
	}
	return arith_express_value_convert(result, &arg1);
}

int do_declare_variable(struct context *ctx, struct expression *express)
{
	struct expression *next = NULL;
	struct variable *var = NULL;
	int ret = 0;

	for (next = express->argv[1]; next != NULL; next = next->argv[1]) {
		struct expression *var_exp = next->argv[0];
		struct arith_express_value result;

		arith_express_value_init(&result, NULL);
		var = malloc(sizeof(struct variable));
		if (var == NULL) {
			return -ENOMEM;
		}

		var->name = var_exp->argv[0];
		ret = arith_express_value_init(&var->value, express->argv[0]);
		if (ret < 0) {
			free(var);
			return ret;
		}

		arith_express_value_print(var->name, &var->value);
		if (var_exp->argv[1] != NULL) {
			ret = do_arithmetic_expression(ctx, var_exp->argv[1],
				&result);
			if (ret < 0) {
				free(var);
				return ret;
			}
		}

		ret = arith_express_value_convert(&var->value, &result);
		if (ret < 0) {
			free(var);
			return ret;
		}
		list_add(&var->list, &current_variable_vector(ctx)->variable_lists);
		arith_express_value_print(var->name, &var->value);
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

	func->retval = express->argv[0];
	ret = arith_express_value_init(&func->freturn_value, express->argv[0]);
	if (ret < 0) {
		free(func->fargv);
		free(func);
		return ret;
	}

	func->arguments = express->argv[2];
	func->fargc = 0;
	for (next = express->argv[2]; next != NULL; next = next->argv[2]) {
		func->fargc++;
	}

	func->fargv = malloc(sizeof(struct variable) * func->fargc);
	if (func->fargv == NULL) {
		free(func);
		return -ENOMEM;
	}

	for (next = express->argv[2]; next != NULL; next = next->argv[2]) {
		struct variable *var = &(func->fargv[i++]);

		ret = arith_express_value_init(&var->value, next->argv[0]);
		if (ret < 0) {
			free(func->fargv);
			free(func);
			return ret;
		}
		var->name = next->argv[1];
		printf("argument: %s\n", var->name);
	}

	func->name = express->argv[1];
	func->express = express->argv[3];
	list_add(&func->list, &ctx->function_lists);
	printf("FUNC name %s: \n", (const char *)express->argv[1]);
	return 0;
}

int do_declare_variable_and_function(struct context *ctx, struct expression *express)
{
	struct expression *next = NULL;

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
	const char *varname = express->argv[0];
	int ret = 0;

	var = variable_find(ctx, varname);
	if (var == NULL) {
		return -EINVAL;
	}

	ret = do_arithmetic_expression(ctx, express->argv[1], &var->value);
	if (ret < 0) {
		return ret;
	}
	arith_express_value_print(varname, &var->value);
	return 0;
}

int do_expressions(struct context *ctx, struct expression *express);

int do_logical_expression(struct context *ctx, struct expression *express)
{
	struct arith_express_value result;
	int ret = 0;

	printf("do %s\n", express->operation);
	arith_express_value_init(&result, NULL);
	if (!strcmp(express->operation, "declare_variable")) {
		return do_declare_variable(ctx, express->argv[0]);
	} else if (!strcmp(express->operation, "expression")) {
		ret = do_arithmetic_expression(ctx, express->argv[0], &result);
		if (ret < 0) {
			return ret;
		}
		return 0;
	} else if (!strcmp(express->operation, "=")) {
		return __do_symbol_equal(ctx, express);
	} else if (!strcmp(express->operation, "while")) {
		do {
			ret = do_arithmetic_expression(ctx, express->argv[0], &result);
			if (ret < 0 || arith_express_value_equal(&result, 0)) {
				return ret;
			}

			ret = do_expressions(ctx, express->argv[1]);
			if (ret < 0) {
				return ret;
			}
		} while (!ctx->flag_returned);
		return 0;
	} else if (!strcmp(express->operation, "if")) {
		ret = do_arithmetic_expression(ctx, express->argv[0], &result);
		if (ret < 0) {
			return ret;
		}

		if (!arith_express_value_equal(&result, 0)) {
			return do_expressions(ctx, express->argv[1]);
		}
		return 0;
	} else if (!strcmp(express->operation, "return")) {
		struct function_runtime *runtime = NULL;

		ret = do_arithmetic_expression(ctx, express->argv[0], &result);
		if (ret < 0) {
			return ret;
		}

		ctx->flag_returned = 1;
		runtime = list_first_entry(&ctx->used_lists,
			struct function_runtime, list);
		arith_express_value_print("return", &result);
		return arith_express_value_convert(&runtime->return_value, &result);
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

int alloc_function_runtime(struct context *ctx, const char *fname,
	struct function_runtime **rfunc_ret)
{
	struct function_runtime *runtime = NULL;
	struct function *pos = NULL, *func = NULL;
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

	runtime = malloc(sizeof(struct function_runtime) +
			sizeof(struct variable) * func->fargc);
	if (runtime == NULL) {
		return -ENOMEM;
	}

	runtime->argc = func->fargc;
	for (i = 0; i < func->fargc; i++) {
		runtime->argv[i] = func->fargv[i];
	}

	INIT_LIST_HEAD(&runtime->variable_vector_lists);
	INIT_LIST_HEAD(&runtime->default_vector.variable_lists);
	list_add_tail(&runtime->default_vector.list, &runtime->variable_vector_lists);

	runtime->func = func;
	runtime->return_value = func->freturn_value;
	*rfunc_ret = runtime;
	return 0;
}

void free_function_runtime(struct function_runtime *runtime)
{
	struct variable *pos, *save;
	struct variable_vector *vector = &runtime->default_vector;

	list_for_each_entry_safe(pos, save, &vector->variable_lists, list) {
		list_del(&pos->list);
		free(pos);
	}

	free(runtime);
}

int do_call_function(struct context *ctx, const char *fname,
	struct arith_express_value *results, const size_t result_size,
	struct arith_express_value *result)
{
	struct function_runtime *runtime = NULL;
	int ret = 0;
	size_t i = 0;

	ret = alloc_function_runtime(ctx, fname, &runtime);
	if (ret < 0 || runtime == NULL) {
		return ret;
	}

	for (i = 0; i < runtime->argc && i < result_size; i++) {
		struct variable *var = &runtime->argv[i];

		ret = arith_express_value_convert(&var->value, &results[i]);
		if (ret < 0) {
			return ret;
		}
	}

	list_add(&runtime->list, &ctx->used_lists);
	ctx->flag_returned = 0;
	ret = do_expressions(ctx, runtime->func->express);
	if (ret < 0) {
		goto out;
	}

	ret = arith_express_value_convert(result, &runtime->return_value);

out:
	ctx->flag_returned = 0;
	list_del(&runtime->list);
	free_function_runtime(runtime);
	return ret;
}

static void free_context(struct context *ctx)
{
	struct function *pos, *save;

	list_for_each_entry_safe(pos, save, &ctx->function_lists, list) {
		list_del(&pos->list);
		if (pos->fargv != NULL) {
			free(pos->fargv);
		}
		free(pos);
	}
}

%}

%union {
	struct expression *express;
	char *strval;
}

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

/*declare tokens */
%token <strval> CMP
%token <strval> NUMBER
%token <strval> SYMBOL
%token IF WHILE RETURN
%token DATA_TYPE_INT DATA_TYPE_FLOAT DATA_TYPE_VOLD DATA_TYPE_STRUCT
%token DATA_TYPE_CHAR

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
	| arithmetic_expression CMP arithmetic_expression { $$ = alloc_expression("cmp", 3, $1, $2, $3); }
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
	struct arith_express_value result;
	int ret = 0;

	yyparse();

	INIT_LIST_HEAD(&ctx.variable_vector.variable_lists);
	INIT_LIST_HEAD(&ctx.function_lists);
	INIT_LIST_HEAD(&ctx.used_lists);

	ret = pretreat_root(&ctx, root);
	if (ret < 0) {
		return ret;
	}

	arith_express_value_init(&result, NULL);
	ret = do_call_function(&ctx, "main", NULL, 0, &result);
	free_context(&ctx);
	return ret;
}

void yyerror(char *s)
{
	fprintf(stderr, "error:%s\n", s);
}
