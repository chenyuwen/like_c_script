%option noyywrap
%{
#include <stdlib.h>
#include "like_c_script.tab.h"
#include "expression.h"

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
"<=" { yylval.strval = TO_EXPRESS(strdup(yytext)); return CMP; }

"if"    { return IF; }
"while" { return WHILE; }
"return" { return RETURN; }
"int" { return DATA_TYPE_INT; }
"char" { return DATA_TYPE_CHAR; }
"float" { return DATA_TYPE_FLOAT; }
"void" { return DATA_TYPE_VOLD; }
"struct" { return DATA_TYPE_STRUCT; }

"//".* {}

[a-zA-Z_]+[0-9a-zA-Z_]* { yylval.strval = TO_EXPRESS(strdup(yytext));return SYMBOL;}

[0-9]+ {yylval.strval = TO_EXPRESS(strdup(yytext));return NUMBER;}
0x[0-9a-fA-F]+ {yylval.strval = TO_EXPRESS(strdup(yytext)); return NUMBER;}
[0-9]+.[0-9]+ {yylval.strval = TO_EXPRESS(strdup(yytext)); return NUMBER;}
[ \t\n]  {}
.  {printf("Mystery character:%c\n", *yytext);}
%%
