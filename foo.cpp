// my function
int foo(int n)
{
  int sum {};
  for( int i{}; i < n; ++ i )
  {
    if((i&1) == 0)
    {
      sum += i;
    }
  }
  return sum;
}