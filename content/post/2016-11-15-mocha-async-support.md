---
author: Ron
catalog: true
date: 2016-11-15T00:00:00Z
header-img: img/post-bg-js-version.jpg
tags:
- javascript
title: mocha异步测试源码分析
url: /2016/11/15/mocha-async-support/
---

mocha异步测试源码分析
<!--more-->

### 使用简介

mocha是一款功能丰富的javascript单元测试框架，它既可以运行在nodejs环境中，也可以运行在浏览器环境中。
javascript是一门单线程语言，最显著的特点就是有很多异步执行。同步代码的测试比较简单，直接判断函数的返回值是否符合预期就行了，而异步的函数，就需要测试框架支持回调、promise或其他的方式来判断测试结果的正确性了。mocha可以良好的支持javascript异步的单元测试。mocha会串行地执行我们编写的测试用例，可以在将未捕获异常指向对应用例的同时，保证输出灵活准确的测试结果报告。


#### 同步测试

```
var assert = require('chai').assert;
describe('Array', function() { //Suite
  describe('#indexOf()', function() {  //Suite could be hierarchically nested
    it('should return -1 when the value is not present', function() { // Test　function
      assert.equal(-1, [1,2,3].indexOf(5));
      assert.equal(-1, [1,2,3].indexOf(0));
    });
  });
});
```

> describe函数的第一个参数会被输出在控制台中，作为一个用例集的描述，而且这个描述是可以根据自己的需求来嵌套输出的，称之为：用例集定义函数。

> it函数第一个参数用来输出一个用例的描述，第二个参数是一个函数，用来编写用例内容，用断言模块来判断结果的正确性，称之为用例函数。

#### 异步测试

只需要在用例函数里边加一个done回调，异步代码执行完毕后调用一下done，就可以通知mocha，去执行下一个用例函数吧，就像下面这样：

```
describe('User', function() {
  describe('#save()', function() {
    it('should save without error', function(done) {
      var user = new User('Luna');
      user.save(function(err) {
        if (err) throw err;
        done();
      });
    });
  });
});
```

### 数据结构

![]({{ site.baseurl }}/img/mocha-data-structure.png)

### 源码分析部分

#### mocha run entrypoint

```
Mocha.prototype.run = function (fn) {
	...

	return runner.run(done);
}

Runner.prototype.run = function (fn) {

	function start () {
		...

	    self.runSuite(rootSuite, function () {
	      debug('finished running');
	      self.emit('end');
	    });
	}
	...

	start()	
}
```

#### run test suite one by one

```
Runner.prototype.runSuite = function (suite, fn) {
	
	...
	function next (errSuite) {
		...
		var curr = suite.suites[i++];
	    if (!curr) {
	      return done();
	    }
	    self.runSuite(curr, next);
	}

	function done (errSuite) {
		...
		self.hook('afterAll', function () {　//'afterAll' hook
	        self.emit('suite end', suite);
	        fn(errSuite);
	    	});
	}

	this.hook('beforeAll', function (err) { //'beforeAll' hook
	    if (err) {
	      return done();
	    }
	    self.runTests(suite, next);
	 });
}
```

#### run test case one by one

```
Runner.prototype.runTests = function (suite, fn) {

	function next (err, errSuite) {
		// next test
	    test = tests.shift();

	    // all done
	    if (!test) {
	      return fn();
	    }
		...
	    self.hookDown('beforeEach', function (err, errSuite) {//'beforeEach' hook
			self.runTest(function (err) {
				...
				self.hookUp('afterEach', next);//'afterEach' hook
			}
	    }

	}
	next();
}
```

#### run each test case with async support

```
Runner.prototype.runTest = function (suite, fn) {
	var test = this.test;
	test.run(fn);
}

Runnable.prototype.run = function (fn) {

	if (this.async) {
		this.resetTimeout();
		try {
	      callFnAsync(this.fn);//this.fn is Runable itself and not the callback fn
	    } catch (err) {
	      emitted = true;
	      done(utils.getError(err));
	    }
	    return;
	}

	function done (err) {
		var ms = self.timeout();
	    if (self.timedOut) {
	      return;
	    }

	    self.clearTimeout();
	    self.duration = new Date() - start;
	    finished = true;
	    if (!err && self.duration > ms && self._enableTimeouts) {
	      err = new Error('Timeout of ' + ms +
	      'ms exceeded. For async tests and hooks, ensure "done()" is called; if returning a Promise, ensure it resolves.');
	    }
	    fn(err);
	}


	function callFnAsync (fn) {
	    var result = fn.call(ctx, function (err) {//this is the done function passed to async test code
	      ...
	      done();
	    });
	}

}
```


