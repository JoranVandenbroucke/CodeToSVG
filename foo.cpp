#include <iostream>

enum class myEnum{
    First,
    Second
};
struct myStruct{
    int id;
    char name;
}
class myClass{
public:
    myClass() = default;
    void display(){
        std::cout << "Inside myClass\n";
    }
}

int main(){
    constexpr int number = 10;
    constexpr char single_quote = '\'';
    // this is a comment
    /* This is
       a multi-line
       comment */
    std::cout << "The number is: " << number << '\n';

    const int array[] = {1,2,3};
    const int value = array[0] + array[1] + -array[2];
    const bool comparison = (value > number);
    const int bitwise = sum | number;
    const int modulo = sum % number;

    myEnum e = myEnum::FIRST;
    myStruct s{1,'a'};
    myClass c{};
    c.display();
    return 0;
}
