---
author: Ron
catalog: true
date: 2016-12-26T00:00:00Z
tags:
- python
title: meta program in python
---

meta program in python
<!--more-->

## *args and **kwargs

```
def test_var_args_call(arg1, arg2, arg3):
    print "arg1:", arg1
    print "arg2:", arg2
    print "arg3:", arg3

args = ("two", 3)
test_var_args_call(1, *args)

result:
arg1: 1
arg2: two
arg3: 3
```

```
def test_var_args_call(arg1, arg2, arg3):
    print "arg1:", arg1
    print "arg2:", arg2
    print "arg3:", arg3

kwargs = {"arg3": 3, "arg2": "two"}
test_var_args_call(1, **kwargs)

result:
arg1: 1
arg2: two
arg3: 3
```

## decorator

```
#coding=utf-8
def a_decorator_passing_arbitrary_arguments(function_to_decorate):
    # 包装函数可以接受任何参数
    def a_wrapper_accepting_arbitrary_arguments(*args, **kwargs):
        print "Do I have args?:"
        print args
        print kwargs
        function_to_decorate(*args, **kwargs)
    return a_wrapper_accepting_arbitrary_arguments

@a_decorator_passing_arbitrary_arguments
def function_with_no_argument():
    print "Python is cool, no argument here."

function_with_no_argument()
#outputs
#Do I have args?:
#()
#{}
#Python is cool, no argument here.

@a_decorator_passing_arbitrary_arguments
def function_with_arguments(a, b, c):
    print a, b, c

function_with_arguments(1,2,3)
#outputs
#Do I have args?:
#(1, 2, 3)
#{}
#1 2 3

@a_decorator_passing_arbitrary_arguments
def function_with_named_arguments(a, b, c, platypus="Why not ?"):
    print "Do %s, %s and %s like platypus? %s" %\
    (a, b, c, platypus)

function_with_named_arguments("Bill", "Linus", "Steve", platypus="Indeed!")
#outputs
#Do I have args ? :
#('Bill', 'Linus', 'Steve')
#{'platypus': 'Indeed!'}
#Do Bill, Linus and Steve like platypus? Indeed!

class Mary(object):
    def __init__(self):
        self.age = 31

    @a_decorator_passing_arbitrary_arguments
    def sayYourAge(self, lie=-3): # You can now add a default value
        print "I am %s, what did you think ?" % (self.age + lie)

m = Mary()
m.sayYourAge()
#outputs
# Do I have args?:
#(<__main__.Mary object at 0xb7d303ac>,)
#{}
#I am 28, what did you think?
```

```
# 装饰 装饰器 的装饰器 (好绕.....)
def decorator_with_args(decorator_to_enhance):
    """
    这个函数将作为装饰器使用
    它必须装饰另一个函数
    它将允许任何接收任意数量参数的装饰器
    方便你每次查询如何实现
    """

    # 同样的技巧传递参数
    def decorator_maker(*args, **kwargs):

        # 创建一个只接收函数的装饰器
        # 但是这里保存了从创建者传递过来的的参数
        def decorator_wrapper(func):

            # 我们返回原始装饰器的结果
            # 这是一个普通的函数，返回值是另一个函数
            # 陷阱：装饰器必须有这个特殊的签名，否则不会生效
            return decorator_to_enhance(func, *args, **kwargs)

        return decorator_wrapper

    return decorator_maker

# 你创建这个函数是作为一个装饰器，但是给它附加了一个装饰器
# 别忘了，函数签名是： "decorator(func, *args, **kwargs)"
@decorator_with_args
def decorated_decorator(func, *args, **kwargs):
    def wrapper(function_arg1, function_arg2):
        print "Decorated with", args, kwargs
        return func(function_arg1, function_arg2)
    return wrapper

# 然后，使用这个装饰器(your brand new decorated decorator)

@decorated_decorator(42, 404, 1024)
def decorated_function(function_arg1, function_arg2):
    print "Hello", function_arg1, function_arg2

decorated_function("Universe and", "everything")
#outputs:
#Decorated with (42, 404, 1024) {}
#Hello Universe and everything
```

## meta class

> type function

先看type函数的使用，要创建一个class对象，type()函数依次传入3个参数：

* class的名称
* 继承的父类集合，注意Python支持多重继承，如果只有一个父类，参考tuple的单元素写法
* class的方法名称与函数绑定，这里我们把函数fn绑定到方法名hello上。

```
>>> def fn(self, name='world'): # 先定义函数
...     print('Hello, %s.' % name)
...
>>> Hello = type('Hello', (object,), dict(hello=fn)) # 创建Hello class
>>> h = Hello()
>>> h.hello()
Hello, world.
>>> print(type(Hello))
<type 'type'>
>>> print(type(h))
<class '__main__.Hello'>
```

> metaclass

```
# metaclass是创建类，所以必须从`type`类型派生：
class ListMetaclass(type):
    def __new__(cls, name, bases, attrs):
        attrs['add'] = lambda self, value: self.append(value)
        return type.__new__(cls, name, bases, attrs)

class MyList(list):
    __metaclass__ = ListMetaclass # 指示使用ListMetaclass来定制类

>>> L = MyList()
>>> L.add(1)
>>> L
[1]
```

__metaclass__ = ListMetaclass语句指示Python解释器在创建MyList时，要通过ListMetaclass.__new__()来创建，在此，我们可以修改类的定义，比如，加上新的方法，然后，返回修改后的定义。__new__()方法接收到的参数依次是：

* 当前准备创建的类的对象；
* 类的名字；
* 类继承的父类集合；
* 类的方法集合。
