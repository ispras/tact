
int f(int i)
{
	return i+1;
}

int main(int c, char** v)
{
	int i = 0;
	int j = 0;
	for(; i < c; ++i)
		j += j*i + i*i + f(i);
	return j;
}
