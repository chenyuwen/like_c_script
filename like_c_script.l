%option noyywrap
%{
#include <stdlib.h>
#include "like_c_script.tab.h"

struct expression *alloc_expression(void);
%}

%%
"+" |
"-" |
"*" |
"/" |
"|" |
"&" |
"(" |
")" |
"," |
"=" |
";" |
"{" |
"}" |
"%" { return yytext[0]; }

"!=" |
"==" |
"<"  |
">"  |
">=" |
"<=" { yylval.strval = strdup(yytext); return CMP; }

"if"    { return IF; }
"while" { return WHILE; }
"return" { return RETURN; }
"int" { return DATA_TYPE_INT; }
"char" { return DATA_TYPE_CHAR; }
"float" { return DATA_TYPE_FLOAT; }
"void" { return DATA_TYPE_VOLD; }
"struct" { return DATA_TYPE_STRUCT; }

"//".* {}

[a-zA-Z_]+[0-9a-zA-Z_]* {yylval.strval = strdup(yytext);return SYMBOL;}

[0-9]+ {yylval.strval = strdup(yytext);return NUMBER;}
0x[0-9a-fA-F]+ {yylval.strval = strdup(yytext); return NUMBER;}
"#".* {}
[ \t\n]  {}
.  {printf("Mystery character:%c\n", *yytext);}
%%
