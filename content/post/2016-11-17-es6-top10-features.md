---
author: Ron
catalog: true
date: 2016-11-17T00:00:00Z
header-img: img/post-bg-js-version.jpg
tags:
- javascript
title: es6 top10 features
url: /2016/11/17/es6-top10-features/
---

es6 top10 features
<!--more-->

Here’s the list of the top 10 best ES6 features for a busy software engineer (in no particular order):

1. Default Parameters in ES6　	
　
2. Template Literals in ES6		
　　
3. Multi-line Strings in ES6　		
　
4. Destructuring Assignment in ES6　
　
5. Enhanced Object Literals in ES6　　

6. Arrow Functions in ES6　　	

7. Promises in ES6　　

8. Block-Scoped Constructs Let and Const　
　
9. Classes in ES6　　

10. Modules in ES6　　

### Default Parameters in ES6

before:

```
var link = function (height, color, url) {
    var height = height || 50
    var color = color || 'red'
    var url = url || 'http://azat.co'
    ...
}
```

after:

```
var link = function(height = 501, color = 'red', url = 'http://azat.co') {
  ...
}
```

### Variable Parameters


函数containsAll可以检查一个字符串中是否包含若干个子串，例如：containsAll("banana", "b", "nan")返回true，containsAll("banana", "c", "nan")返回false。

before:

```
function containsAll(haystack) {
  for (var i = 1; i < arguments.length; i++) {
    var needle = arguments[i];
    if (haystack.indexOf(needle) === -1) {
      return false;
    }
  }
  return true;
}
```

after:

```
function containsAll(haystack, ...needles) {
  for (var needle of needles) {
    if (haystack.indexOf(needle) === -1) {
      return false;
    }
  }
  return true;
}
```

### Template Literals in ES6

before:

```
var name = 'Your name is ' + first + ' ' + last + '.'
var url = 'http://localhost:3000/api/messages/' + id
```

after:

```
var name = `Your name is ${first} ${last}.`
var url = `http://localhost:3000/api/messages/${id}`
```

### Multi-line Strings in ES6

before:

```
var roadPoem = 'Then took the other, as just as fair,\n\t'
    + 'And having perhaps the better claim\n\t'
    + 'Because it was grassy and wanted wear,\n\t'
    + 'Though as for that the passing there\n\t'
    + 'Had worn them really about the same,\n\t'

var fourAgreements = 'You have the right to be you.\n\
    You can only be you when you do your best.'
```

after:

```
var roadPoem = `Then took the other, as just as fair,
    And having perhaps the better claim
    Because it was grassy and wanted wear,
    Though as for that the passing there
    Had worn them really about the same,`

var fourAgreements = `You have the right to be you.
    You can only be you when you do your best.`
```

### Destructuring Assignment in ES6

before:

```
var data = $('body').data(), // data has properties house and mouse
  house = data.house,
  mouse = data.mouse

var jsonMiddleware = require('body-parser').json

var body = req.body, // body has username and password
  username = body.username,
  password = body.password  
```

after:

```
var { house, mouse} = $('body').data() // we'll get house and mouse variables

var {jsonMiddleware} = require('body-parser')

var {username, password} = req.body

//also works with arrays
var [col1, col2]  = $('.column'),
[line1, line2, line3, , line5] = file.split('\n')
```

### Enhanced Object Literals in ES6

before:

```
var serviceBase = {port: 3000, url: 'azat.co'},
    getAccounts = function(){return [1,2,3]}

var accountServiceES5 = {
  port: serviceBase.port,
  url: serviceBase.url,
  getAccounts: getAccounts,
  toString: function() {
    return JSON.stringify(this.valueOf())
  },
  getUrl: function() {return "http://" + this.url + ':' + this.port},
  valueOf_1_2_3: getAccounts()
}
```
after:

```
var serviceBase = {port: 3000, url: 'azat.co'},
    getAccounts = function(){return [1,2,3]}
var accountService = {
    __proto__: serviceBase,
    getAccounts,
    toString() {
     return JSON.stringify((super.valueOf()))
    },
    getUrl() {return "http://" + this.url + ':' + this.port},
    [ 'valueOf_' + getAccounts().join('_') ]: getAccounts()
};
console.log(accountService)

```

### Arrow Functions in ES6
before:

```
var _this = this
$('.btn').click(function(event){
  _this.sendData()
})

var logUpperCase = function() {
  var _this = this

  this.string = this.string.toUpperCase()
  return function () {
    return console.log(_this.string)
  }
}

logUpperCase.call({ string: 'es6 rocks' })()

var ids = ['5632953c4e345e145fdf2df8','563295464e345e145fdf2df9']
var messages = ids.map(function (value) {
  return "ID is " + value // explicit return
});

var ids = ['5632953c4e345e145fdf2df8', '563295464e345e145fdf2df9'];
var messages = ids.map(function (value, index, list) {
  return 'ID of ' + index + ' element is ' + value + ' ' // explicit return
});
```
after:

```
$('.btn').click((event) =>{
  this.sendData()
})

var logUpperCase = function() {
  this.string = this.string.toUpperCase()
  return () => console.log(this.string)
}

logUpperCase.call({ string: 'es6 rocks' })()

var ids = ['5632953c4e345e145fdf2df8','563295464e345e145fdf2df9']
var messages = ids.map(value => `ID is ${value}`) // implicit return

var ids = ['5632953c4e345e145fdf2df8','563295464e345e145fdf2df9']
var messages = ids.map((value, index, list) => `ID of ${index} element is ${value} `) // implicit return
```

### Promises in ES6

before:

```
setTimeout(function(){
  console.log('Yay!')
  setTimeout(function(){
    console.log('Wheeyee!')
  }, 1000)
}, 1000)
```
after:

```
var wait1000 =  ()=> new Promise((resolve, reject)=> {setTimeout(resolve, 1000)})

wait1000()
    .then(function() {
        console.log('Yay!')
        return wait1000()
    })
    .then(function() {
        console.log('Wheeyee!')
    });
}
```

### Block-Scoped Constructs Let and Const

before:

```
function calculateTotalAmount (vip) {
  var amount = 0
  if (vip) {
    var amount = 1
  }
  { // more crazy blocks!
    var amount = 100
    {
      var amount = 1000
      }
  }  
  return amount
}

console.log(calculateTotalAmount(true))//return 1000
```
after:

```
function calculateTotalAmount (vip) {
  var amount = 0 // probably should also be let, but you can mix var and let
  if (vip) {
    let amount = 1 // first amount is still 0
  } 
  { // more crazy blocks!
    let amount = 100 // first amount is still 0
    {
      let amount = 1000 // first amount is still 0
      }
  }  
  return amount
}

console.log(calculateTotalAmount(true))//return 0

function calculateTotalAmount (vip) {
  const amount = 0  
  if (vip) {
    const amount = 1 
  } 
  { // more crazy blocks!
    const amount = 100 
    {
      const amount = 1000
      }
  }  
  return amount
}

console.log(calculateTotalAmount(true))//return 0
```

### Classes in ES6

```
class baseModel {
  constructor(options = {}, data = []) { // class constructor
        this.name = 'Base'
    this.url = 'http://azat.co/api'
        this.data = data
    this.options = options
    }

    getName() { // class method
        console.log(`Class name: ${this.name}`)
    }
}

class AccountModel extends baseModel {
    constructor(options, data) {
	    super({private: true}, ['32113123123', '524214691']) //call the parent method with super
	    this.name = 'Account Model'
	    this.url +='/accounts/'
    }
    get accountsData() { //calculated attribute getter
    // ... make XHR
        return this.data
    } 

let accounts = new AccountModel(5)
accounts.getName()
console.log('Data is %s', accounts.accountsData)   
```

### Modules in ES6


before:

```
module.exports = {
  port: 3000,
  getAccounts: function() {
    ...
  }
}

var service = require('module.js')
console.log(service.port) // 3000
```
after:

```
export var port = 3000
export function getAccounts(url) {
  ...
}

import {port, getAccounts} from 'module'
console.log(port) // 3000

import * as service from 'module'
console.log(service.port) // 3000
```

### Proxy and Reflect

```
function Tree() {
      return new Proxy({}, handler);
    }
    var handler = {
      get: function (target, key, receiver) {
        if (!(key in target)) {
          target[key] = Tree();  // 自动创建一个子树
        }
        return Reflect.get(target, key, receiver);
      }
    };


 var tree = Tree();
    > tree
        { }
    > tree.branch1.branch2.twig = "green";
    > tree
        { branch1: { branch2: { twig: "green" } } }
    > tree.branch1.branch3.twig = "yellow";
        { branch1: { branch2: { twig: "green" },
                     branch3: { twig: "yellow" }}}
```

### Generators in ES6

```
function *foo() {
    yield 1;
    return 2;
}

var it = foo();

console.log( it.next() ); // { value:1, done:false }
console.log( it.next() ); // { value:2, done:true }

function *foo(x) {
    var y = 2 * (yield (x + 1));
    var z = yield (y / 3);
    return (x + y + z);
}

var it = foo( 5 );

// note: not sending anything into `next()` here
console.log( it.next() );       // { value:6, done:false }
console.log( it.next( 12 ) );   // { value:8, done:false }
console.log( it.next( 13 ) );   // { value:42, done:true }

function *foo() {
    yield 1;
    yield 2;
    yield 3;
    yield 4;
    yield 5;
    return 6;
}

for (var v of foo()) {
    console.log( v );
}
// 1 2 3 4 5

console.log( v ); // still `5`, not `6`



function* outer() {
    yield 'begin';

    /*
     * yield* 一般用来在一个 generator 函数里“执行”另一个 generator 函数，并可以取得其返回值
     */
    var rt = yield* inner();
    console.log(rt);  // -> 输出：return from inner

    yield 'end';
}

function* inner() {
    yield 'inner';
    return 'return from inner';
}

var it = outer(), v;

v = it.next().value;
console.log(v);            // -> 输出：begin

v = it.next().value;
console.log(v);            // -> 输出：inner

v = it.next().value;
console.log(v);            // -> 输出：end
```


### Generator and Promise together to avoid callback hell

```
function request(url) {
    return new Promise( function(resolve,reject){
        // pass an error-first style callback
        makeAjaxCall( url, function(err,text){
            if (err) reject( err );
            else resolve( text );
        } );
    } );
}

// run (async) a generator to completion
// Note: simplified approach: no error handling here
function runGenerator(g) {
    var it = g(), ret;

    // asynchronously iterate over generator
    (function iterate(val){
        ret = it.next( val );

        if (!ret.done) {
            // poor man's "is it a promise?" test
            if ("then" in ret.value) {
                // wait on the promise
                ret.value.then( iterate );
            }
            // immediate value: just send right back in
            else {
                // avoid synchronous recursion
                setTimeout( function(){
                    iterate( ret.value );
                }, 0 );
            }
        }
    })();
}

runGenerator( function *main(){
    try {
        var result1 = yield request( "http://some.url.1" );
    }
    catch (err) {
        console.log( "Error: " + err );
        return;
    }
    var data = JSON.parse( result1 );

    try {
        var result2 = yield request( "http://some.url.2?id=" + data.id );
    } catch (err) {
        console.log( "Error: " + err );
        return;
    }
    var resp = JSON.parse( result2 );
    console.log( "The value you asked for: " + resp.value );
} );
```