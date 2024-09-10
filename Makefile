like_c_script: like_c_script.l like_c_script.y
	bison -Wcounterexamples -d like_c_script.y
	flex like_c_script.l
	gcc -o $@ like_c_script.tab.c lex.yy.c
clean:
	rm -rf like_c_script.tab.c lex.yy.c like_c_script like_c_script.tab.h
