 
void simputch(uint8_t d)
{
   _putch(d);
   volatile int t;
   t=d;
}

uint8_t array[256];
uint8_t buf[4];

void sieve()
{
   int number,index,t0;
   uint8_t  t;
   
   t0=TCNT;
   array[0]=0xff;
   for (t=1;t;t++) array[t]=0xff;
   
   for (number=2;number<2048;number++) {
       if (array[number>>3]&(1<<(number&7))) {
           //print number
	   index=number;
	   t=0;
	   do {
	       buf[t++]=(index%10)+'0';
	       index/=10;
	   } while (index);
	   do {
	       simputch(buf[--t]);
	   } while (t);
	   simputch(' ');
	   
	   for (index=number+number;index<2048;index+=number) {
	       array[index>>3]&=~(1<<(index&7));
	   }
       }
   }
   t0=TCNT-t0;
   _printf("\n%d us\n",t0/(CCLK/1000000));
}
