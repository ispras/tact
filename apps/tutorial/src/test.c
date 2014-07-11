#include <stdio.h>

#ifndef SLOW
  #ifndef FAST
    #define MULT 1000000
  #else
    #ifndef EVEN_FASTER
      #define MULT 100
    #else
      #define MULT 1
    #endif
  #endif
#else
  #define MULT 3000000
#endif

#ifdef MISCOMPILE
  #define MIS 0
#else
  #define MIS 1
#endif


int main(int argc, char *argv[])
{

#ifdef MISCOMPILE
  printf("Miscompiled source code.\n");
  exit(139);
#endif
  unsigned int *a,i;
  a = (unsigned int*)malloc(argc*sizeof(unsigned int)*MULT*MIS);

  for(i = 0; i<argc*MULT; i++)
  {
    a[i] = a[i]>>4;
  }

#ifdef SLOW
  printf("5 - slow (%i)\n",a[argc%2]+MULT);
#else
#ifdef FAST
#ifdef EVEN_FASTER
  printf("90 - very fast (%i)\n",a[argc%2]+MULT);
#else
  printf("30 - fast (%i)\n",a[argc%2]+MULT);
#endif
#else
  printf("10 - normal (%i)\n",a[argc%2]+MULT);
#endif
#endif
  
  // Return normal hash of test:
  printf("HASH=123\n");

  return 0;
}
