#include <stdio.h>

int main(int argc, char* argv[]){
	int i,a = 0,b=1,c=10;
	char *str = NULL;
	if(argc>1)
		str = argv[1];
	if(str == NULL)
		return 1;
	for(i = 0; i < 12; i++)
	{
		b += i;
		c = b;
	}
	for(i = 0; i < 12; i++)
		a += (int)(str[i]);
	for(i = 0; i<12; i++)
		if (i < 5)
			a += b/6;
	if (a>0xff1)
		a = a/4;
	if (a<50)
		a = a + 0x101;
	if (b != 73)
	{
		a += 12;
		c = a;
	}

	printf("Rendering %i milliseconds\n", a);
	return 0;
}
