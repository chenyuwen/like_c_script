test4: test4.l test4.y
	bison -Wcounterexamples -d test4.y
	flex test4.l
	gcc -o $@ test4.tab.c lex.yy.c
clean:
	rm -rf test4.tab.c lex.yy.c test4 test4.tab.h
