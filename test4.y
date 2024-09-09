%{
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <limits.h>
#include "gnu_list.h"

int yylex();
void yyerror(char *s);

enum {
	EXP_NUMBER,
	EXP_CALLFUNC,
	EXP_TWO_PARAM,
	EXP_SINGLE_PARAM,
	EXP_ASSIGN,
	EXP_VAR,
};

enum {
	CMP_NOT_EQUAL,
	CMP_EQUAL,
	CMP_
};

struct expression {
	int type;

	union {
		const char *number;
		const char *varname;

		struct {
			const char *name;
			struct expression *argument;
		};

		struct {
			char operation;
			struct expression *arg1, *arg2;
		};
	};
};

struct variable {
	struct list_head list;
	const char *name;
	int intval;
};

struct expression *alloc_number_expression(const char *number)
{
	struct expression *express = NULL;

	express = malloc(sizeof(struct expression));
	if (express == NULL) {
		printf("%s: alloc memory failed.\n", __func__);
		return NULL;
	}

	express->type = EXP_NUMBER;
	express->number = number;
	return express;
}

struct expression *alloc_var_expression(const char *varname)
{
	struct expression *express = NULL;

	express = malloc(sizeof(struct expression));
	if (express == NULL) {
		printf("%s: alloc memory failed.\n", __func__);
		return NULL;
	}

	express->type = EXP_VAR;
	express->varname = varname;
	return express;
}

struct expression *alloc_callfunc_expression(const char *funcname,
	struct expression *argument)
{
	struct expression *express = NULL;

	express = malloc(sizeof(struct expression));
	if (express == NULL) {
		printf("%s: alloc memory failed.\n", __func__);
		return NULL;
	}

	express->type = EXP_CALLFUNC;
	express->name = funcname;
	express->argument = argument;
	return express;
}

struct expression *alloc_two_param_expression(struct expression *arg1, char operation,
	struct expression *arg2)
{
	struct expression *express = NULL;

	express = malloc(sizeof(struct expression));
	if (express == NULL) {
		printf("%s: alloc memory failed.\n", __func__);
		return NULL;
	}

	express->type = EXP_TWO_PARAM;
	express->operation = operation;
	express->arg1 = arg1;
	express->arg2 = arg2;
	return express;
}

struct expression *alloc_single_param_expression(char operation, struct expression *arg)
{
	struct expression *express = NULL;

	express = malloc(sizeof(struct expression));
	if (express == NULL) {
		printf("%s: alloc memory failed.\n", __func__);
		return NULL;
	}

	express->type = EXP_SINGLE_PARAM;
	express->operation = operation;
	express->arg1 = arg;
	return express;
}

struct expression *alloc_assign_expression(const char *argname,
	struct expression *argument)
{
	struct expression *express = NULL;

	express = malloc(sizeof(struct expression));
	if (express == NULL) {
		printf("%s: alloc memory failed.\n", __func__);
		return NULL;
	}

	express->type = EXP_ASSIGN;
	express->name = argname;
	express->argument = argument;
	return express;
}

extern int expression_run(struct expression *express);

int do_func_min(struct expression *express)
{
	int ret = INT_MAX, newval = 0;
	struct expression *next = NULL;

	for (next = express->argument; next != NULL; next = next->arg2) {
		switch (next->operation) {
		case 'A':
			newval = expression_run(next->arg1);
			break;
		default:
			newval = expression_run(next);
			break;
		}

		if (newval < ret) {
			ret = newval;
		}
	}

	return ret;
}

int do_func_max(struct expression *express)
{
	int ret = 0, newval = 0;
	struct expression *next = NULL;

	for (next = express->argument; next != NULL; next = next->arg2) {
		switch (next->operation) {
		case 'A':
			newval = expression_run(next->arg1);
			break;
		default:
			newval = expression_run(next);
			break;
		}
		if (newval > ret) {
			ret = newval;
		}
	}

	return ret;
}

int do_func_print(struct expression *express)
{
	int ret = 0, newval = 0;
	struct expression *next = NULL;

	for (next = express->argument; next != NULL; next = next->arg2) {
		switch (next->operation) {
		case 'A':
			newval = expression_run(next->arg1);
			break;
		default:
			newval = expression_run(next);
			break;
		}
		printf("%d\n", newval);
	}

	return ret;
}

int do_callfunc(struct expression *express)
{
	int ret = 0;

	if (!strcmp(express->name, "MIN")) {
		return do_func_min(express);
	} else if (!strcmp(express->name, "MAX")) {
		return do_func_max(express);
	} else if (!strcmp(express->name, "PRINT")) {
		return do_func_print(express);
	}
	return 0;
}

int do_two_param(struct expression *express)
{
	switch (express->operation) {
	case '+':
		return expression_run(express->arg1) + expression_run(express->arg2);
	case '-':
		return expression_run(express->arg1) - expression_run(express->arg2);
	case '*':
		return expression_run(express->arg1) * expression_run(express->arg2);
	case '/':
		return expression_run(express->arg1) / expression_run(express->arg2);
	case '&':
		return expression_run(express->arg1) & expression_run(express->arg2);
	case '|':
		return expression_run(express->arg1) | expression_run(express->arg2);

	case 'I':
		if (expression_run(express->arg1)) {
			expression_run(express->arg2);
		}
		return 0;
	case 'W':
		while (expression_run(express->arg1)) {
			expression_run(express->arg2);
		}
		return 0;
	}
}

int do_single_param(struct expression *express)
{
	int ret = 0;
	switch (express->operation) {
	case '-':
		return -expression_run(express->arg1);
	case '(':
		return expression_run(express->arg1);
	case '|':
		ret = expression_run(express->arg1);
		if (ret < 0) {
			return -ret;
		}
		return ret;
	}
}

int do_number(struct expression *express)
{
	if (!strncmp(express->number, "0x", 2)) {
		return strtol(express->number, NULL, 16);
	}
	return strtol(express->number, NULL, 10);
}

struct list_head variable_list = LIST_HEAD_INIT(variable_list);
int do_assign(struct expression *express)
{
	struct variable *pos = NULL, *var = NULL;

	list_for_each_entry(pos, &variable_list, list) {
		if (!strcmp(pos->name, express->name)) {
			var = pos;
			break;
		}
	}

	if (var == NULL) {
		var = malloc(sizeof(struct variable));
		if (var == NULL) {
			return -1;
		}

		var->name = express->name;
		list_add(&var->list, &variable_list);
	}

	var->intval = expression_run(express->argument);
	return 0;
}

int do_var(struct expression *express)
{
	struct variable *pos = NULL;

	list_for_each_entry(pos, &variable_list, list) {
		if (!strcmp(pos->name, express->name)) {
			return pos->intval;
		}
	}
	return 0;
}

int expression_run(struct expression *express)
{
	switch (express->type) {
	case EXP_NUMBER:
		return do_number(express);
	case EXP_VAR:
		return do_var(express);
	case EXP_CALLFUNC:
		return do_callfunc(express);
	case EXP_TWO_PARAM:
		return do_two_param(express);
	case EXP_SINGLE_PARAM:
		return do_single_param(express);
	case EXP_ASSIGN:
		return do_assign(express);
	}

	return 0;
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

%type <express> exp arguments explist
%type <express> declare_variable_and_function declare_variable_and_functions
%type <express> function_arguments declare_varible
%token <intval> CMP
%token IF WHILE RETURN
%token DATA_TYPE_INT DATA_TYPE_FLOAT

%%

calclist:
	| declare_variable_and_functions { printf("# "); }
	;

declare_variable_and_functions:
	  declare_variable_and_function {}
	| declare_variable_and_functions declare_variable_and_function {}
	;

declare_variable_and_function:
	  declare_varible ';' {printf("dec0\n"); }
	| declare_function {}
	;

declare_varible:
	  data_type varible_symbols { printf("dec3\n");}
	;

varible_symbols:
	  varible_symbol {}
	| varible_symbol ',' varible_symbols {}
	;

varible_symbol:
	  SYMBOL {}
	| SYMBOL '=' exp {}
	;

data_type:
	  DATA_TYPE_INT
	| DATA_TYPE_FLOAT
	;

declare_function:
	  SYMBOL '(' function_arguments ')' '{' '}' { printf("func %s\n", $1);}
	| SYMBOL '(' function_arguments ')' '{' explist '}' { printf("func %s\n", $1);}
	;

function_arguments:
	  { printf("%d\n", __LINE__); }
	| data_type SYMBOL { printf("%d\n", __LINE__); }
	| data_type SYMBOL ',' function_arguments { printf("%d\n", __LINE__); }
	;

explist:
 	  one_exp {}
	| one_exp explist {printf("explist5\n"); }
	;

one_exp:
	  exp ';' {printf("%d\n", __LINE__); }
	| declare_varible ';' {printf("dec1\n"); }
	| RETURN exp ';' {printf("return\n"); }
	| WHILE '(' exp ')' '{' explist '}' {printf("while\n"); }
	| WHILE '(' exp ')' '{' '}' {printf("while\n"); }
	| IF '(' exp ')' '{' explist '}' {  }
	| IF '(' exp ')' '{' '}' {  }
	;

exp:
          exp '+' exp {  }
	| exp '-' exp {  }
	| exp '*' exp {  }
	| exp '/' exp {  }
	| exp '&' exp {  }
	| exp '|' exp {  }
	| '|' exp '|' {  }
	| '(' exp ')' {  }
	| '-' exp     {  }
	| NUMBER      {  }
	| SYMBOL      {  }
	| SYMBOL '(' arguments ')' {  }
	| SYMBOL '=' exp {  }
	;

arguments:
	  { }
	| exp { }
	| exp ',' arguments {  }
	;
%%

int main(int argc, char ** argv)
{
	printf("# ");
	yyparse();
}

void yyerror(char *s)
{
	fprintf(stderr, "error:%s\n", s);
}
