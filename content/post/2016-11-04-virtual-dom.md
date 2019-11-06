---
author: Ron
catalog: true
date: 2016-11-04T00:00:00Z
header-img: img/post-bg-js-version.jpg
tags:
- react
- javascript
title: reactjs源码分析
url: /2016/11/04/virtual-dom/
---

reactjs virtual dom 源码分析
<!--more-->

reactjs的核心内容并不多，主要是下面这些:

- 虚拟dom对象(Virtual DOM)
- 虚拟dom差异化算法（diff algorithm）
- 单向数据流渲染（Data Flow）
- 组件生命周期
- 事件处理

下面我们将一点点的来实现一个简易版的reactjs，实现上面的那些功能，最后用这个reactjs做一个todolist的小应用，看完这个，或者跟着敲一遍代码。希望让大家能够更好的理解reactjs的运行原理。实例源码都托管在[github](https://github.com/yrong/little-reactjs)。点这里里面有分步骤的例子，可以一边看一边运行例子。

## 首次渲染

#### 基本骨架

下面我们将一点点的来实现一个简易版的reactjs(仅仅使用jquery)，实现上面的那些功能,先从渲染hello world开始看下面的代码：

```
<script type="text/javascript">
React.render('hello world',document.getElementById("container"))
</script>

/**
对应的html为

<div id="container"></div>


生成后的html为：

<div id="container">
    <span data-reactid="0">hello world</span>
</div>

*/

```
假定这一行代码,就可以把hello world渲染到对应的div里面。我们来看看我们需要为此做些什么：


```
//component类，用来表示文本在渲染，更新，删除时应该做些什么事情
function ReactDOMTextComponent(text) {
    //存下当前的字符串
    this._currentElement = '' + text;
    //用来标识当前component
    this._rootNodeID = null;
}

//component渲染时生成的dom结构
ReactDOMTextComponent.prototype.mountComponent = function(rootID) {
    this._rootNodeID = rootID;
    return '<span data-reactid="' + rootID + '">' + this._currentElement + '</span>';
}


//component工厂  用来返回一个component实例
function instantiateReactComponent(node){
    if(typeof node === 'string' || typeof node === 'number'){ //暂时只支持文本
        return new ReactDOMTextComponent(node)
    }
}


React = {
    nextReactRootIndex:0,
    render:function(element,container){

        var componentInstance = instantiateReactComponent(element);
        var markup = componentInstance.mountComponent(React.nextReactRootIndex++);
        $(container).html(markup);
        //触发完成mount的事件
        $(document).trigger('mountReady');    }
}
```

代码分为三个部分：

1. React.render 作为入口负责调用渲染
2. 引入了component类的概念，ReactDOMTextComponent是一个component类定义，定义对于这种文本类型的节点，在渲染，更新，删除时应该做什么操作，这边暂时只用到渲染，另外两个可以先忽略
3. instantiateReactComponent用来根据element的类型（现在只有一种string类型），返回一个component的实例。其实就是个类工厂。

nextReactRootIndex作为每个component的标识id，不断加1，确保唯一性。这样我们以后可以通过这个标识找到这个元素。可以看到我们把逻辑分为几个部分，主要的渲染逻辑放在了具体的componet类去定义。React.render负责调度整个流程，这里是调用instantiateReactComponent生成一个对应component类型的实例对象，然后调用此对象的mountComponent获取生成的内容。最后写到对应的container节点中。


#### HTML元素

我们希望Component(虚拟dom)类型除了文本之外支持浏览器自带的基本元素比如`div　p input form`这种，比如在hello world外面包一层div,并且带上一些属性，甚至事件时我们可以这么写：

```
//演示事件监听怎么用
function hello(){
    alert('hello')
}

//假设我们把虚拟dom模型定义成类似{ type: '…', props: { … }, children: [ … ] }这样的数据结构
var element = React.createElement('div',{id:'test',onclick:hello},'click me')

React.render(element,document.getElementById("container"))


/**

//生成的html为：

<div data-reactid="0" id="test">
    <span data-reactid="0.0">click me</span>
</div>


//点击文字，会弹出hello的对话框

*/
```

我们来看看简易版本React.createElement的实现：

```
//ReactElement就是虚拟dom的概念，具有一个type属性代表当前的节点类型，还有节点的属性props
//比如对于div这样的节点type就是div，props就是那些attributes
//另外这里的key,可以用来标识这个element，用于优化以后的更新，这里可以先不管，知道有这么个东西就好了
function ReactElement(type,key,props){
  this.type = type;
  this.key = key;
  this.props = props;
}


React = {
    nextReactRootIndex:0,
    createElement:function(type,config,children){
        var props = {},propName;
        config = config || {}
        //看有没有key，用来标识element的类型，方便以后高效的更新，这里可以先不管
        var key = config.key || null;

        //复制config里的内容到props
        for (propName in config) {
            if (config.hasOwnProperty(propName) && propName !== 'key') {
                props[propName] = config[propName];
            }
        }

        //处理children,全部挂载到props的children属性上
        //支持两种写法，如果只有一个参数，直接赋值给children，否则做合并处理
        var childrenLength = arguments.length - 2;
        if (childrenLength === 1) {
            props.children = $.isArray(children) ? children : [children] ;
        } else if (childrenLength > 1) {
            var childArray = Array(childrenLength);
            for (var i = 0; i < childrenLength; i++) {
                childArray[i] = arguments[i + 2];
            }
            props.children = childArray;
        }

        return new ReactElement(type, key,props);

    },
    render:function(element,container){
        var componentInstance = instantiateReactComponent(element);
        var markup = componentInstance.mountComponent(React.nextReactRootIndex++);
        $(container).html(markup);
        //触发完成mount的事件
        $(document).trigger('mountReady');
    }
}

```

增加了createElement函数返回一个ReactElement实例对象也就是我们说的虚拟元素的实例。有了元素实例，我们得把他渲染出来，此时render接受的是一个ReactElement而不是文本，我们先改造下instantiateReactComponent：

```
function instantiateReactComponent(node){
    //文本节点的情况
    if(typeof node === 'string' || typeof node === 'number'){
        return new ReactDOMTextComponent(node);
    }
    //浏览器默认节点的情况
    if(typeof node === 'object' && typeof node.type === 'string'){
        //注意这里，使用了一种新的component
        return new ReactDOMComponent(node);

    }
}
```

增加了一个判断，这样当render的不是文本而是浏览器的基本元素时。我们使用另外一种component来处理它渲染时应该返回的内容。这里就体现了工厂方法instantiateReactComponent的好处了，不管来了什么类型的node，都可以负责生产出一个负责渲染的component实例。这样render完全不需要做任何修改，只需要再做一种对应的component类型（这里是ReactDOMComponent）就行了。所以重点我们来看看ReactDOMComponent的具体实现：

```
//component类，用来表示文本在渲染，更新，删除时应该做些什么事情
function ReactDOMComponent(element){
    //存下当前的element对象引用
    this._currentElement = element;
    this._rootNodeID = null;
}

//component渲染时生成的dom结构
ReactDOMComponent.prototype.mountComponent = function(rootID){
    //赋值标识
    this._rootNodeID = rootID;
    var props = this._currentElement.props;
    var tagOpen = '<' + this._currentElement.type;
    var tagClose = '</' + this._currentElement.type + '>';

    //加上reactid标识
    tagOpen += ' data-reactid=' + this._rootNodeID;

    //拼凑出属性
    for (var propKey in props) {

        //这里要做一下事件的监听，就是从属性props里面解析拿出on开头的事件属性的对应事件监听
        if (/^on[A-Za-z]/.test(propKey)) {
            var eventType = propKey.replace('on', '');
            //针对当前的节点添加事件代理,以_rootNodeID为命名空间
            $(document).delegate('[data-reactid="' + this._rootNodeID + '"]', eventType + '.' + this._rootNodeID, props[propKey]);
        }

        //对于children属性以及事件监听的属性不需要进行字符串拼接
        //事件会代理到全局。这边不能拼到dom上不然会产生原生的事件监听
        if (props[propKey] && propKey != 'children' && !/^on[A-Za-z]/.test(propKey)) {
            tagOpen += ' ' + propKey + '=' + props[propKey];
        }
    }
    //获取子节点渲染出的内容
    var content = '';
    var children = props.children || [];

    var childrenInstances = []; //用于保存所有的子节点的componet实例，以后会用到
    var that = this;
    $.each(children, function(key, child) {
        //这里再次调用了instantiateReactComponent实例化子节点component类，拼接好返回
        var childComponentInstance = instantiateReactComponent(child);
        childComponentInstance._mountIndex = key;

        childrenInstances.push(childComponentInstance);
        //子节点的rootId是父节点的rootId加上新的key也就是顺序的值拼成的新值
        var curRootId = that._rootNodeID + '.' + key;
        //得到子节点的渲染内容
        var childMarkup = childComponentInstance.mountComponent(curRootId);
        //拼接在一起
        content += ' ' + childMarkup;

    })

    //留给以后更新时用的这边先不用管
    this._renderedChildren = childrenInstances;

    //拼出整个html内容
    return tagOpen + '>' + content + tagClose;
}
```

我们增加了虚拟dom reactElement的定义，增加了一个新的componet类ReactDOMComponent。这样我们就实现了渲染浏览器基本元素的功能了。对于虚拟dom的渲染逻辑，本质上还是个递归渲染的东西，reactElement会递归渲染自己的子节点。可以看到我们通过instantiateReactComponent屏蔽了子节点的差异，只需要使用不同的componet类，这样都能保证通过mountComponent最终拿到渲染后的内容。另外这边的事件也要说下，可以在传递props的时候传入{onClick:function(){}}这样的参数，这样就会在当前元素上添加事件，代理到document `$(document).delegate('[data-reactid="' + this._rootNodeID + '"]', eventType + '.' + this._rootNodeID, props[propKey]);` 由于reactjs本身全是在写js，所以监听的函数的传递变得特别简单。

>   这里很多东西没有考虑，比如一些特殊的类型input select等等，再比如img不需要有对应的tagClose等。这里为了保持简单就不再扩展了。另外reactjs的事件处理其实很复杂，实现了一套标准的w3c事件。这里偷懒直接使用jQuery的事件代理到document上了。

#### 自定义组合元素

下面实现自定义元素的功能。我们上面element.type只是个简单的字符串，如果是个类呢？如果这个类恰好还有自己的生命周期管理，那扩展性就很高了。还是先看看reactjs怎么使用自定义元素，从使用反推实现：

```
var HelloMessage = React.createClass({
  getInitialState: function() {
    return {type: 'say:'};
  },
  componentWillMount: function() {
    console.log('我就要开始渲染了。。。')
  },
  componentDidMount: function() {
    console.log('我已经渲染好了。。。')
  },
  render: function() {
    return React.createElement("div", null,this.state.type, "Hello ", this.props.name);
  }
});


React.render(React.createElement(HelloMessage, {name: "John"}), document.getElementById("container"));

/**
结果为：

html:
<div data-reactid="0">
    <span data-reactid="0.0">say:</span>
    <span data-reactid="0.1">Hello </span>
    <span data-reactid="0.2">John</span>
</div>

console:
我就要开始渲染了。。。
我已经渲染好了。。。

*/
```
React.createElement接受的不再是字符串，而是一个class。React.createClass生成一个自定义标记类，带有基本的生命周期：

- getInitialState 获取最初的属性值this.state
- componentWillmount 在组件准备渲染时调用
- componentDidMount 在组件渲染完成后调用

对reactjs稍微有点了解的应该都可以明白上面的用法,先来看看React.createClass的实现：

```
//定义ReactClass类,所有自定义的超级父类
var ReactClass = function(){
}
//留给子类去继承覆盖
ReactClass.prototype.render = function(){}



React = {
    nextReactRootIndex:0,
    createClass:function(spec){
        //生成一个子类
        var Constructor = function (props) {
            this.props = props;
            this.state = this.getInitialState ? this.getInitialState() : null;
        }
        //原型继承，继承超级父类
        Constructor.prototype = new ReactClass();
        Constructor.prototype.constructor = Constructor;
        //混入spec到原型
        $.extend(Constructor.prototype,spec);
        return Constructor;

    },
    createElement:function(type,config,children){
        ...
    },
    render:function(element,container){
        ...
    }
}
```
可以看到createClass生成了一个继承ReactClass的子类，在构造函数里调用this.getInitialState获得最初的state。

>   为了演示方便,我们这边的ReactClass相当简单，实际上原始的代码处理了很多东西，比如类的mixin的组合继承支持,比如componentDidMount等可以定义多次，需要合并调用等等，有兴趣的去翻源码吧，不是本文的主要目的，这里就不详细展开了。

我们这里只是返回了一个继承类的定义，那么具体的componentWillmount，这些生命周期函数在哪里调用呢。看看我们上面的两种类型就知道，我们是时候为自定义元素也提供一个componet类了，在那个类里我们会实例化ReactClass，并且管理生命周期，还有父子组件依赖。老规矩先改造instantiateReactComponent:

```
function instantiateReactComponent(node){
    //文本节点的情况
    if(typeof node === 'string' || typeof node === 'number'){
        return new ReactDOMTextComponent(node);
    }
    //浏览器默认节点的情况
    if(typeof node === 'object' && typeof node.type === 'string'){
        //注意这里，使用了一种新的component
        return new ReactDOMComponent(node);

    }
    //自定义的元素节点
    if(typeof node === 'object' && typeof node.type === 'function'){
        //注意这里，使用新的component,专门针对自定义元素
        return new ReactCompositeComponent(node);

    }
}
```
很简单我们增加了一个判断，使用新的component类形来处理自定义的节点。我们看下ReactCompositeComponent的具体实现:

```
function ReactCompositeComponent(element){
    //存放元素element对象
    this._currentElement = element;
    //存放唯一标识
    this._rootNodeID = null;
    //存放对应的ReactClass的实例
    this._instance = null;
}

//用于返回当前自定义元素渲染时应该返回的内容
ReactCompositeComponent.prototype.mountComponent = function(rootID){
    this._rootNodeID = rootID;
    //拿到当前元素对应的属性值
    var publicProps = this._currentElement.props;
    //拿到对应的ReactClass
    var ReactClass = this._currentElement.type;
    // Initialize the public class
    var inst = new ReactClass(publicProps);
    this._instance = inst;
    //保留对当前comonent的引用，下面更新会用到
    inst._reactInternalInstance = this;

    if (inst.componentWillMount) {
        inst.componentWillMount();
        //这里在原始的reactjs其实还有一层处理，就是  componentWillMount调用setstate，不会触发rerender而是自动提前合并，这里为了保持简单，就略去了
    }
    //调用ReactClass的实例的render方法,返回一个element或者一个文本节点
    var renderedElement = this._instance.render();
    //得到renderedElement对应的component类实例
    var renderedComponentInstance = instantiateReactComponent(renderedElement);
    this._renderedComponent = renderedComponentInstance; //存起来留作后用

    //拿到渲染之后的字符串内容，将当前的_rootNodeID传给render出的节点
    var renderedMarkup = renderedComponentInstance.mountComponent(this._rootNodeID);

    //之前我们在React.render方法最后触发了mountReady事件，所以这里可以监听，在渲染完成后会触发。
    $(document).on('mountReady', function() {
        //调用inst.componentDidMount
        inst.componentDidMount && inst.componentDidMount();
    });

    return renderedMarkup;
}
```
实现并不难，ReactClass的render一定是返回一个虚拟节点(包括element和text)，这个时候我们使用instantiateReactComponent去得到实例，再使用mountComponent拿到结果作为当前自定义元素的结果。应该说本身自定义元素不负责具体的内容，他更多的是负责生命周期。具体的内容是由它的render方法返回的虚拟节点来负责渲染的。本质上也是递归的去渲染内容的过程。同时因为这种递归的特性，父组件的componentWillMount一定在某个子组件的componentWillMount之前调用，而父组件的componentDidMount肯定在子组件之后．上面实现了三种类型的元素，其实我们发现本质上没有太大的区别，都是有自己对应component类来处理自己的渲染过程。大概的关系是下面这样。

![]({{ site.baseurl }}/img/TB1NPA_JpXXXXcVXXXXXXXXXXXX-1024-768.jpg)

## 更新机制

#### 节点比较算法原理

在React中，树的算法其实非常简单，那就是两棵树只会对同一层次的节点进行比较。如下图所示：

![]({{ site.baseurl }}/img/0909000.png)

React只会对相同颜色方框内的DOM节点进行比较，即同一个父节点下的所有子节点。当发现节点已经不存在，则该节点及其子节点会被完全删除掉，不会用于进一步的比较。这样只需要对树进行一次遍历，便能完成整个DOM树的比较。

#### 相同类型节点的比较

第二种节点的比较是相同类型的节点，算法就相对简单而容易理解。React会对属性进行重设从而实现节点的转换。例如：

```
renderA: <div id="before" />
renderB: <div id="after" />
=> [replaceAttribute id "after"]
```
虚拟DOM的style属性稍有不同，其值并不是一个简单字符串而必须为一个对象，因此转换过程如下：

```
renderA: <div style={{color: 'red'}} />
renderB: <div style={{fontWeight: 'bold'}} />
=> [removeStyle color], [addStyle font-weight 'bold']
```

#### 不同节点类型的比较

当一个节点从div变成span时，简单的直接删除div节点，并插入一个新的span节点。

```
renderA: <div />
renderB: <span />
=> [removeNode <div />], [insertNode <span />]
```

例如，考虑有下面的DOM结构转换：

![]({{ site.baseurl }}/img/0909001.png)

A节点被整个移动到D节点下，直观的考虑DOM Diff操作应该是

```
A.parent.remove(A); 
D.append(A);
```

但因为React只会简单的考虑同层节点的位置变换，对于不同层的节点，只有简单的创建和删除。当根节点发现子节点中A不见了，就会直接销毁A；而当D发现自己多了一个子节点A，则会创建一个新的A作为子节点。因此对于这种结构的转变的实际操作是：

```
A.destroy();
A = new A();
A.append(new B());
A.append(new C());
D.append(A);
```

可以看到，以A为根节点的树被整个重新创建。


#### 算法实现

虚拟dom差异化算法（diff algorithm）是reactjs最核心的东西，按照官方的说法。他非常快，非常高效。目前已经有一些分析此算法的文章，但是仅仅停留在表面。所以我们下面自己动手实现一遍，等你完全实现了，再去看那些文字图片流的介绍文章，就会发现容易理解多了。一般在reactjs中我们需要更新时都是调用的setState。看下面的例子：

```
var HelloMessage = React.createClass({
  getInitialState: function() {
    return {type: 'say:'};
  },
  changeType:function(){
    this.setState({type:'shout:'})
  },
  render: function() {
    return React.createElement("div", {onclick:this.changeType},this.state.type, "Hello ", this.props.name);
  }
});


React.render(React.createElement(HelloMessage, {name: "John"}), document.getElementById("container"));



/**

//生成的html为：

<div data-reactid="0" id="test">
    <span data-reactid="0.0">say hello world</span>
</div>

点击文字，say会变成shout

*/
```

点击文字，调用setState就会更新，所以我们扩展下ReactClass，看下setState的实现：

```
//定义ReactClass类
var ReactClass = function(){
}

ReactClass.prototype.render = function(){}

//setState
ReactClass.prototype.setState = function(newState) {

    //还记得我们在ReactCompositeComponent里面mount的时候 做了赋值
    //所以这里可以拿到 对应的ReactCompositeComponent的实例_reactInternalInstance
    this._reactInternalInstance.receiveComponent(null, newState);
}
```

可以看到setState主要调用了对应的component的receiveComponent来实现更新。所有的挂载，更新都应该交给对应的component来管理。就像所有的component都实现了mountComponent来处理第一次渲染，所有的componet类都应该实现receiveComponent用来处理自己的更新。

#### 自定义元素的receiveComponent

所以我们照葫芦画瓢来给自定义元素的对应component类（ReactCompositeComponent）实现一个receiveComponent方法：

```
//更新
ReactCompositeComponent.prototype.receiveComponent = function(nextElement, newState) {

    //如果接受了新的，就使用最新的element
    this._currentElement = nextElement || this._currentElement

    var inst = this._instance;
    //合并state
    var nextState = $.extend(inst.state, newState);
    var nextProps = this._currentElement.props;


    //改写state
    inst.state = nextState;


    //如果inst有shouldComponentUpdate并且返回false。说明组件本身判断不要更新，就直接返回。
    if (inst.shouldComponentUpdate && (inst.shouldComponentUpdate(nextProps, nextState) === false)) return;

    //生命周期管理，如果有componentWillUpdate，就调用，表示开始要更新了。
    if (inst.componentWillUpdate) inst.componentWillUpdate(nextProps, nextState);


    var prevComponentInstance = this._renderedComponent;
    var prevRenderedElement = prevComponentInstance._currentElement;
    //重新执行render拿到对应的新element;
    var nextRenderedElement = this._instance.render();


    //判断是需要更新还是直接就重新渲染
    //注意这里的_shouldUpdateReactComponent跟上面的不同哦 这个是全局的方法
    if (_shouldUpdateReactComponent(prevRenderedElement, nextRenderedElement)) {
        //如果需要更新，就继续调用子节点的receiveComponent的方法，传入新的element更新子节点。
        prevComponentInstance.receiveComponent(nextRenderedElement);
        //调用componentDidUpdate表示更新完成了
        inst.componentDidUpdate && inst.componentDidUpdate();

    } else {
        //如果发现完全是不同的两种element，那就干脆重新渲染了
        var thisID = this._rootNodeID;
        //重新new一个对应的component，
        this._renderedComponent = this._instantiateReactComponent(nextRenderedElement);
        //重新生成对应的元素内容
        var nextMarkup = _renderedComponent.mountComponent(thisID);
        //替换整个节点
        $('[data-reactid="' + this._rootNodeID + '"]').replaceWith(nextMarkup);

    }

}

//用来判定两个element需不需要更新
//这里的key是我们createElement的时候可以选择性的传入的。用来标识这个element，当发现key不同时，我们就可以直接重新渲染，不需要去更新了。
var _shouldUpdateReactComponent ＝ function(prevElement, nextElement){
    if (prevElement != null && nextElement != null) {
    var prevType = typeof prevElement;
    var nextType = typeof nextElement;
    if (prevType === 'string' || prevType === 'number') {
      return nextType === 'string' || nextType === 'number';
    } else {
      return nextType === 'object' && prevElement.type === nextElement.type && prevElement.key === nextElement.key;
    }
  }
  return false;
}
```

不要被这么多代码吓到，其实流程很简单。它主要做了什么事呢？首先会合并改动，生成最新的state,props然后拿以前的render返回的element跟现在最新调用render生成的element进行对比（_shouldUpdateReactComponent），看看需不需要更新，如果要更新就继续调用对应的component类对应的receiveComponent就好啦，其实就是直接当甩手掌柜，事情直接丢给手下去办了。当然还有种情况是，两次生成的element差别太大，就不是一个类型的，那好办直接重新生成一份新的代码重新渲染一次就o了。本质上还是递归调用receiveComponent的过程。这里注意两个函数：

- inst.shouldComponentUpdate是实例方法，当我们不希望某次setState后更新，我们就可以重写这个方法，返回false就好了。
- _shouldUpdateReactComponent是一个全局方法，这个是一种reactjs的优化机制。用来决定是直接全部替换，还是使用很细微的改动。当两次render出来的子节点key不同，直接全部重新渲染一遍，替换就好了。否则，我们就得来个递归的更新，保证最小化的更新机制，这样可以不会有太大的闪烁。另外可以看到这里还处理了一套更新的生命周期调用机制。

#### 文本节点的receiveComponent

我们再看看文本节点的，比较简单：

```
ReactDOMTextComponent.prototype.receiveComponent = function(nextText) {
    var nextStringText = '' + nextText;
    //跟以前保存的字符串比较
    if (nextStringText !== this._currentElement) {
        this._currentElement = nextStringText;
        //替换整个节点
        $('[data-reactid="' + this._rootNodeID + '"]').html(this._currentElement);

    }
}
```
没什么好说的，如果不同的话，直接找到对应的节点，更新就好了。

#### 基本元素element的receiveComponent

最后我们开始看比较复杂的浏览器基本元素的更新机制。比如我们看看下面的html:

```
<div id="test" name="hello">
    <span></span>
    <span></span>
</div>
```

想一下我们怎么以最小代价去更新这段html呢。不难发现其实主要包括两个部分：

1. 属性的更新，包括对特殊属性比如事件的处理
2. 子节点的更新,这个比较复杂，为了得到最好的效率，我们需要处理下面这些问题：
    拿新的子节点树跟以前老的子节点树对比，找出他们之间的差别。我们称之为diff
    所有差别找出后，再一次性的去更新。我们称之为patch

所以更新代码结构如下：

```
ReactDOMComponent.prototype.receiveComponent = function(nextElement) {
    var lastProps = this._currentElement.props;
    var nextProps = nextElement.props;

    this._currentElement = nextElement;
    //需要单独的更新属性
    this._updateDOMProperties(lastProps, nextProps);
    //再更新子节点
    this._updateDOMChildren(nextElement.props.children);
}
```

整体上也不复杂，先是处理当前节点属性的变动，后面再去处理子节点的变动.我们一步步来，先看看，更新属性怎么变更：

```
ReactDOMComponent.prototype._updateDOMProperties = function(lastProps, nextProps) {
    var propKey;
    //遍历，当一个老的属性不在新的属性集合里时，需要删除掉。

    for (propKey in lastProps) {
        //新的属性里有，或者propKey是在原型上的直接跳过。这样剩下的都是不在新属性集合里的。需要删除
        if (nextProps.hasOwnProperty(propKey) || !lastProps.hasOwnProperty(propKey)) {
            continue;
        }
        //对于那种特殊的，比如这里的事件监听的属性我们需要去掉监听
        if (/^on[A-Za-z]/.test(propKey)) {
            var eventType = propKey.replace('on', '');
            //针对当前的节点取消事件代理
            $(document).undelegate('[data-reactid="' + this._rootNodeID + '"]', eventType, lastProps[propKey]);
            continue;
        }

        //从dom上删除不需要的属性
        $('[data-reactid="' + this._rootNodeID + '"]').removeAttr(propKey)
    }

    //对于新的属性，需要写到dom节点上
    for (propKey in nextProps) {
        //对于事件监听的属性我们需要特殊处理
        if (/^on[A-Za-z]/.test(propKey)) {
            var eventType = propKey.replace('on', '');
            //以前如果已经有，说明有了监听，需要先去掉
            lastProps[propKey] && $(document).undelegate('[data-reactid="' + this._rootNodeID + '"]', eventType, lastProps[propKey]);
            //针对当前的节点添加事件代理,以_rootNodeID为命名空间
            $(document).delegate('[data-reactid="' + this._rootNodeID + '"]', eventType + '.' + this._rootNodeID, nextProps[propKey]);
            continue;
        }

        if (propKey == 'children') continue;

        //添加新的属性，或者是更新老的同名属性
        $('[data-reactid="' + this._rootNodeID + '"]').prop(propKey, nextProps[propKey])
    }

}
```

属性的变更并不是特别复杂，主要就是找到以前老的不用的属性直接去掉，新的属性赋值，并且注意其中特殊的事件属性做出特殊处理就行了。下面我们看子节点的更新，也是最复杂的部分。

```
ReactDOMComponent.prototype.receiveComponent = function(nextElement){
    var lastProps = this._currentElement.props;
    var nextProps = nextElement.props;

    this._currentElement = nextElement;
    //需要单独的更新属性
    this._updateDOMProperties(lastProps,nextProps);
    //再更新子节点
    this._updateDOMChildren(nextProps.children);
}

//全局的更新深度标识
var updateDepth = 0;
//全局的更新队列，所有的差异都存在这里
var diffQueue = [];

ReactDOMComponent.prototype._updateDOMChildren = function(nextChildrenElements){
    updateDepth++
    //_diff用来递归找出差别,组装差异对象,添加到更新队列diffQueue。
    this._diff(diffQueue,nextChildrenElements);
    updateDepth--
    if(updateDepth == 0){
        //在需要的时候调用patch，执行具体的dom操作
        this._patch(diffQueue);
        diffQueue = [];
    }
}
```

就像我们之前说的一样，更新子节点包含两个部分，一个是递归的分析差异，把差异添加到队列中。然后在合适的时机调用_patch把差异应用到dom上。那么什么是合适的时机，updateDepth又是干嘛的？这里需要注意的是，_diff内部也会递归调用子节点的receiveComponent于是当某个子节点也是浏览器普通节点，就也会走_updateDOMChildren这一步。所以这里使用了updateDepth来记录递归的过程，只有等递归回来updateDepth为0时，代表整个差异已经分析完毕，可以开始使用patch来处理差异队列了。所以我们关键是实现_diff与_patch两个方法。我们先看_diff的实现：

```
//差异更新的几种类型
var UPATE_TYPES = {
    MOVE_EXISTING: 1,
    REMOVE_NODE: 2,
    INSERT_MARKUP: 3
}


//普通的children是一个数组，此方法把它转换成一个map,key就是element的key,如果是text节点或者element创建时并没有传入key,就直接用在数组里的index标识
function flattenChildren(componentChildren) {
    var child;
    var name;
    var childrenMap = {};
    for (var i = 0; i < componentChildren.length; i++) {
        child = componentChildren[i];
        name = child && child._currentelement && child._currentelement.key ? child._currentelement.key : i.toString(36);
        childrenMap[name] = child;
    }
    return childrenMap;
}


//主要用来生成子节点elements的component集合
//这边注意，有个判断逻辑，如果发现是更新，就会继续使用以前的componentInstance,调用对应的receiveComponent。
//如果是新的节点，就会重新生成一个新的componentInstance，
function generateComponentChildren(prevChildren, nextChildrenElements) {
    var nextChildren = {};
    nextChildrenElements = nextChildrenElements || [];
    $.each(nextChildrenElements, function(index, element) {
        var name = element.key ? element.key : index;
        var prevChild = prevChildren && prevChildren[name];
        var prevElement = prevChild && prevChild._currentElement;
        var nextElement = element;

        //调用_shouldUpdateReactComponent判断是否是更新
        if (_shouldUpdateReactComponent(prevElement, nextElement)) {
            //更新的话直接递归调用子节点的receiveComponent就好了
            prevChild.receiveComponent(nextElement);
            //然后继续使用老的component
            nextChildren[name] = prevChild;
        } else {
            //对于没有老的，那就重新新增一个，重新生成一个component
            var nextChildInstance = instantiateReactComponent(nextElement, null);
            //使用新的component
            nextChildren[name] = nextChildInstance;
        }
    })

    return nextChildren;
}



//_diff用来递归找出差别,组装差异对象,添加到更新队列diffQueue。
ReactDOMComponent.prototype._diff = function(diffQueue, nextChildrenElements) {
  var self = this;
  //拿到之前的子节点的 component类型对象的集合,这个是在刚开始渲染时赋值的，记不得的可以翻上面
  //_renderedChildren 本来是数组，我们搞成map
  var prevChildren = flattenChildren(self._renderedChildren);
  //生成新的子节点的component对象集合，这里注意，会复用老的component对象
  var nextChildren = generateComponentChildren(prevChildren, nextChildrenElements);
  //重新赋值_renderedChildren，使用最新的。
  self._renderedChildren = []
  $.each(nextChildren, function(key, instance) {
    self._renderedChildren.push(instance);
  })


  var nextIndex = 0; //代表到达的新的节点的index
  //通过对比两个集合的差异，组装差异节点添加到队列中
  for (name in nextChildren) {
    if (!nextChildren.hasOwnProperty(name)) {
      continue;
    }
    var prevChild = prevChildren && prevChildren[name];
    var nextChild = nextChildren[name];
    //相同的话，说明是使用的同一个component,所以我们需要做移动的操作
    if (prevChild === nextChild) {
      //添加差异对象，类型：MOVE_EXISTING
      diffQueue.push({
        parentId: self._rootNodeID,
        parentNode: $('[data-reactid=' + self._rootNodeID + ']'),
        type: UPATE_TYPES.MOVE_EXISTING,
        fromIndex: prevChild._mountIndex,
        toIndex: nextIndex
      })
    } else { //如果不相同，说明是新增加的节点
      //但是如果老的还存在，就是element不同，但是component一样。我们需要把它对应的老的element删除。
      if (prevChild) {
        //添加差异对象，类型：REMOVE_NODE
        diffQueue.push({
          parentId: self._rootNodeID,
          parentNode: $('[data-reactid=' + self._rootNodeID + ']'),
          type: UPATE_TYPES.REMOVE_NODE,
          fromIndex: prevChild._mountIndex,
          toIndex: null
        })

        //如果以前已经渲染过了，记得先去掉以前所有的事件监听，通过命名空间全部清空
        if (prevChild._rootNodeID) {
            $(document).undelegate('.' + prevChild._rootNodeID);
        }

      }
      //新增加的节点，也组装差异对象放到队列里
      //添加差异对象，类型：INSERT_MARKUP
      diffQueue.push({
        parentId: self._rootNodeID,
        parentNode: $('[data-reactid=' + self._rootNodeID + ']'),
        type: UPATE_TYPES.INSERT_MARKUP,
        fromIndex: null,
        toIndex: nextIndex,
        markup: nextChild.mountComponent() //新增的节点，多一个此属性，表示新节点的dom内容
      })
    }
    //更新mount的index
    nextChild._mountIndex = nextIndex;
    nextIndex++;
  }



  //对于老的节点里有，新的节点里没有的那些，也全都删除掉
  for (name in prevChildren) {
    if (prevChildren.hasOwnProperty(name) && !(nextChildren && nextChildren.hasOwnProperty(name))) {
      //添加差异对象，类型：REMOVE_NODE
      diffQueue.push({
        parentId: self._rootNodeID,
        parentNode: $('[data-reactid=' + self._rootNodeID + ']'),
        type: UPATE_TYPES.REMOVE_NODE,
        fromIndex: prevChild._mountIndex,
        toIndex: null
      })
      //如果以前已经渲染过了，记得先去掉以前所有的事件监听
      if (prevChildren[name]._rootNodeID) {
        $(document).undelegate('.' + prevChildren[name]._rootNodeID);
      }
    }
  }
}
```

我们分析下上面的代码，咋一看好多，好复杂，不急我们从入口开始看。首先我们拿到之前的component的集合，如果是第一次更新的话，这个值是我们在渲染时赋值的。然后我们调用generateComponentChildren生成最新的component集合。我们知道component是用来放element的，一个萝卜一个坑。注意flattenChildren我们这里把数组集合转成了对象map,以element的key作为标识，当然对于text文本或者没有传入key的element,直接用index作为标识。通过这些标识，我们可以从类型的角度来判断两个component是否是一样的。generateComponentChildren会尽量的复用以前的component，也就是那些坑，当发现可以复用component（也就是key一致）时，就还用以前的，只需要调用他对应的更新方法receiveComponent就行了，这样就会递归的去获取子节点的差异对象然后放到队列了。如果发现不能复用那就是新的节点，我们就需要instantiateReactComponent重新生成一个新的component。

>   这里的flattenChildren需要给予很大的关注，比如对于一个表格列表，我们在最前面插入了一条数据，想一下如果我们创建element时没有传入key，所有的key都是null,这样reactjs在generateComponentChildren时就会默认通过顺序（index）来一一对应改变前跟改变后的子节点，这样变更前与变更后的对应节点判断（_shouldUpdateReactComponent）其实是不合适的。也就是说对于这种列表的情况，我们最好给予唯一的标识key，这样reactjs找对应关系时会更方便一点

当我们生成好新的component集合以后，我们需要做出对比。组装差异对象。对比老的集合和新的集合。我们需要找出涵盖四种情况，包括三种类型（UPATE_TYPES）的变动：

类型 | 情况
MOVE_EXISTING  | 新的component类型在老的集合里也有，并且element是可以更新的类型，在generateComponentChildren我们已经调用了receiveComponent，这种情况下prevChild=nextChild,那我们就需要做出移动的操作，可以复用以前的dom节点。
INSERT_MARKUP   |新的component类型不在老的集合里，那么就是全新的节点，我们需要插入新的节点
REMOVE_NODE |老的component类型，在新的集合里也有，但是对应的element不同了不能直接复用直接更新，那我们也得删除。
REMOVE_NODE |老的component不在新的集合里的，我们需要删除

所以我们找出了这三种类型的差异，组装成具体的差异对象，然后加到了差异队列里面。比如我们看下面这个例子，假设下面这些是某个父元素的子元素集合，上面到下面代表了变动流程：

![]({{ site.baseurl }}/img/TB1oUcQJpXXXXawXVXXXXXXXXXX-1024-768.jpg)

数字我们可以理解为给element的key。正方形代表element。圆形代表了component。当然也是实际上的dom节点的位置。从上到下，我们的4 2 1里 2 ，1可以复用之前的component,让他们通知自己的子节点更新后，再告诉2和1，他们在新的集合里需要移动的位置（在我们这里就是组装差异对象加到队列）。3需要删除，4需要新增。好了，整个的diff就完成了，这个时候当递归完成，我们就需要开始做patch的动作了，把这些差异对象实打实的反映到具体的dom节点上。我们看下_patch的实现：

```
//用于将childNode插入到指定位置
function insertChildAt(parentNode, childNode, index) {
    var beforeChild = parentNode.children().get(index);
    beforeChild ? childNode.insertBefore(beforeChild) : childNode.appendTo(parentNode);
}

ReactDOMComponent.prototype._patch = function(updates) {
    var update;
    var initialChildren = {};
    var deleteChildren = [];
    for (var i = 0; i < updates.length; i++) {
        update = updates[i];
        if (update.type === UPATE_TYPES.MOVE_EXISTING || update.type === UPATE_TYPES.REMOVE_NODE) {
            var updatedIndex = update.fromIndex;
            var updatedChild = $(update.parentNode.children().get(updatedIndex));
            var parentID = update.parentID;

            //所有需要更新的节点都保存下来，方便后面使用
            initialChildren[parentID] = initialChildren[parentID] || [];
            //使用parentID作为简易命名空间
            initialChildren[parentID][updatedIndex] = updatedChild;


            //所有需要修改的节点先删除,对于move的，后面再重新插入到正确的位置即可
            deleteChildren.push(updatedChild)
        }

    }

    //删除所有需要先删除的
    $.each(deleteChildren, function(index, child) {
        $(child).remove();
    })


    //再遍历一次，这次处理新增的节点，还有修改的节点这里也要重新插入
    for (var k = 0; k < updates.length; k++) {
        update = updates[k];
        switch (update.type) {
            case UPATE_TYPES.INSERT_MARKUP:
                insertChildAt(update.parentNode, $(update.markup), update.toIndex);
                break;
            case UPATE_TYPES.MOVE_EXISTING:
                insertChildAt(update.parentNode, initialChildren[update.parentID][update.fromIndex], update.toIndex);
                break;
            case UPATE_TYPES.REMOVE_NODE:
                // 什么都不需要做，因为上面已经帮忙删除掉了
                break;
        }
    }
}
```

_patch主要就是挨个遍历差异队列，遍历两次，第一次删除掉所有需要变动的节点，然后第二次插入新的节点还有修改的节点。这里为什么可以直接挨个的插入呢？原因就是我们在diff阶段添加差异节点到差异队列时，本身就是有序的，也就是说对于新增节点（包括move和insert的）在队列里的顺序就是最终dom的顺序，所以我们才可以挨个的直接根据index去塞入节点。但是其实你会发现这里有个问题，就是所有的节点都会被删除，包括复用以前的component类型为UPATE_TYPES.MOVE_EXISTING的，所以闪烁会很严重。其实我们再看看上面的例子，其实2是不需要记录到差异队列的。这样后面patch也是ok的。想想是为什么呢？我们来改造下代码：

```
//_diff用来递归找出差别,组装差异对象,添加到更新队列diffQueue。
ReactDOMComponent.prototype._diff = function(diffQueue, nextChildrenElements){
    。。。
    /**注意新增代码**/
    var lastIndex = 0;//代表访问的最后一次的老的集合的位置
    var nextIndex = 0;//代表到达的新的节点的index
    //通过对比两个集合的差异，组装差异节点添加到队列中
    for (name in nextChildren) {
        if (!nextChildren.hasOwnProperty(name)) {
          continue;
        }
        var prevChild = prevChildren && prevChildren[name];
        var nextChild = nextChildren[name];
        //相同的话，说明是使用的同一个component,所以我们需要做移动的操作
        if (prevChild === nextChild) {
          //添加差异对象，类型：MOVE_EXISTING
          。。。。
          /**注意新增代码**/
          prevChild._mountIndex < lastIndex && diffQueue.push({
                parentId:this._rootNodeID,
                parentNode:$('[data-reactid='+this._rootNodeID+']'),
                type: UPATE_TYPES.REMOVE_NODE,
                fromIndex: prevChild._mountIndex,
                toIndex:null
          })
          lastIndex = Math.max(prevChild._mountIndex, lastIndex);
        } else {
          //如果不相同，说明是新增加的节点，
          if (prevChild) {
            //但是如果老的还存在，就是element不同，但是component一样。我们需要把它对应的老的element删除。
            //添加差异对象，类型：REMOVE_NODE
            。。。。。
            /**注意新增代码**/
            lastIndex = Math.max(prevChild._mountIndex, lastIndex);
          }
          。。。
        }
        //更新mount的inddex
        nextChild._mountIndex = nextIndex;
        nextIndex++;
      }

      //对于老的节点里有，新的节点里没有的那些，也全都删除掉
      。。。
}
```

如下图，老集合中包含节点：A、B、C、D，更新后的新集合中包含节点：B、A、D、C，此时新老集合进行 diff 差异化对比，发现 B != A，则创建并插入 B 至新集合，删除老集合 A；以此类推，创建并插入 A、D 和 C，删除 B、C 和 D。

![]({{ site.baseurl }}/img/2111537988-56fe2b9eaeb62_articlex.jpeg)

React 发现这类操作繁琐冗余，因为这些都是相同的节点，但由于位置发生变化，导致需要进行繁杂低效的删除、创建操作，其实只要对这些节点进行位置移动即可。针对这一现象，React 提出优化策略：允许开发者对同一层级的同组子节点，添加唯一key进行区分，虽然只是小小的改动，性能上却发生了翻天覆地的变化！新老集合所包含的节点，如下图所示，新老集合进行diff差异化对比，通过key发现新老集合中的节点都是相同的节点，因此无需进行节点删除和创建，只需要将老集合中节点的位置进行移动，更新为新集合中节点的位置，此时 React 给出的 diff 结果为：B、D 不做任何操作，A、C 进行移动操作，即可。

![]({{ site.baseurl }}/img/1450771059-56fe2ba43c916_articlex.jpeg)

以上图为例，可以更为清晰直观的描述 diff 的差异对比过程：

首先对新集合的节点进行循环遍历，for (name in nextChildren)，通过唯一 key 可以判断新老集合中是否存在相同的节点，if (prevChild === nextChild)，如果存在相同节点，则进行移动操作，但在移动前需要将当前节点在老集合中的位置与 lastIndex 进行比较，if (child._mountIndex < lastIndex)，则进行节点移动操作，否则不执行该操作。这是一种顺序优化手段，lastIndex一直在更新，表示访问过的节点在老集合中最右的位置（即最大的位置），如果新集合中当前访问的节点比 lastIndex 大，说明当前访问节点在老集合中就比上一个节点位置靠后，则该节点不会影响其他节点的位置，因此不用添加到差异队列中，即不执行移动操作，只有当访问的节点比 lastIndex 小时，才需要进行移动操作。

- 从新集合中取得 B，判断老集合中存在相同节点 B，通过对比节点位置判断是否进行移动操作，B 在老集合中的位置 B._mountIndex = 1，此时 lastIndex = 0，不满足 child._mountIndex < lastIndex 的条件，因此不对 B 进行移动操作；更新 lastIndex = Math.max(prevChild._mountIndex, lastIndex)，其中 prevChild._mountIndex 表示 B 在老集合中的位置，则 lastIndex ＝ 1，并将 B 的位置更新为新集合中的位置 prevChild._mountIndex = nextIndex，此时新集合中 B._mountIndex = 0，nextIndex++ 进入下一个节点的判断。

- 从新集合中取得 A，判断老集合中存在相同节点 A，通过对比节点位置判断是否进行移动操作，A 在老集合中的位置 A._mountIndex = 0，此时 lastIndex = 1，满足 child._mountIndex < lastIndex的条件，因此对 A 进行移动操作enqueueMove(this, child._mountIndex, toIndex)，其中 toIndex 其实就是 nextIndex，表示 A 需要移动到的位置；更新 lastIndex = Math.max(prevChild._mountIndex, lastIndex)，则 lastIndex ＝ 1，并将 A 的位置更新为新集合中的位置 prevChild._mountIndex = nextIndex，此时新集合中 A._mountIndex = 1，nextIndex++ 进入下一个节点的判断。

- 从新集合中取得 D，判断老集合中存在相同节点 D，通过对比节点位置判断是否进行移动操作，D 在老集合中的位置 D._mountIndex = 3，此时 lastIndex = 1，不满足 child._mountIndex < lastIndex的条件，因此不对 D 进行移动操作；更新 lastIndex = Math.max(prevChild._mountIndex, lastIndex)，则 lastIndex ＝ 3，并将 D 的位置更新为新集合中的位置 prevChild._mountIndex = nextIndex，此时新集合中 D._mountIndex = 2，nextIndex++ 进入下一个节点的判断。

- 从新集合中取得 C，判断老集合中存在相同节点 C，通过对比节点位置判断是否进行移动操作，C 在老集合中的位置 C._mountIndex = 2，此时 lastIndex = 3，满足 child._mountIndex < lastIndex 的条件，因此对 C 进行移动操作 enqueueMove(this, child._mountIndex, toIndex)；更新 lastIndex = Math.max(prevChild._mountIndex, lastIndex)，则 lastIndex ＝ 3，并将 C 的位置更新为新集合中的位置 prevChild._mountIndex = nextIndex，此时新集合中 A._mountIndex = 3，nextIndex++ 进入下一个节点的判断，由于 C 已经是最后一个节点，因此 diff 到此完成。


以上主要分析新老集合中存在相同节点但位置不同时，对节点进行位置移动的情况，如果新集合中有新加入的节点且老集合存在需要删除的节点，那么 React diff 又是如何对比运作的呢？

以下图为例：

- 从新集合中取得 B，判断老集合中存在相同节点 B，由于 B 在老集合中的位置 B._mountIndex = 1，此时 lastIndex = 0，因此不对 B 进行移动操作；更新 lastIndex ＝ 1，并将 B 的位置更新为新集合中的位置 B._mountIndex = 0，nextIndex++进入下一个节点的判断。
- 从新集合中取得 E，判断老集合中不存在相同节点 E，则创建新节点 E；更新 lastIndex ＝ 1，并将 E 的位置更新为新集合中的位置，nextIndex++进入下一个节点的判断。
- 从新集合中取得 C，判断老集合中存在相同节点 C，由于 C 在老集合中的位置C._mountIndex = 2，此时 lastIndex = 1，因此对 C 进行移动操作；更新 lastIndex ＝ 2，并将 C 的位置更新为新集合中的位置，nextIndex++ 进入下一个节点的判断。
- 从新集合中取得 A，判断老集合中存在相同节点 A，由于 A 在老集合中的位置A._mountIndex = 0，此时 lastIndex = 2，因此不对 A 进行移动操作；更新 lastIndex ＝ 2，并将 A 的位置更新为新集合中的位置，nextIndex++ 进入下一个节点的判断。
- 当完成新集合中所有节点 diff 时，最后还需要对老集合进行循环遍历，判断是否存在新集合中没有但老集合中仍存在的节点，发现存在这样的节点 D，因此删除节点 D，到此 diff 全部完成。

![]({{ site.baseurl }}/img/703547875-56fe2bb3d3157_articlex.jpeg)

可以看到我们多加了个lastIndex，这个代表最后一次访问的老集合节点的最大的位置。而我们加了个判断，只有_mountIndex小于这个lastIndex的才会需要加入差异队列。有了这个判断上面的例子2就不需要move。而程序也可以好好的运行，实际上大部分都是2这种情况。这是一种顺序优化，lastIndex一直在更新，代表了当前访问的最右的老的集合的元素。我们假设上一个元素是A,添加后更新了lastIndex。如果我们这时候来个新元素B，比lastIndex还大说明当前元素在老的集合里面就比上一个A靠后。所以这个元素就算不加入差异队列，也不会影响到其他人，不会影响到后面的path插入节点。因为我们从patch里面知道，新的集合都是按顺序从头开始插入元素的，只有当新元素比lastIndex小时才需要变更。其实只要仔细推敲下上面那个例子，就可以理解这种优化手段了。这样整个的更新机制就完成了。



我们再来简单回顾下reactjs的差异算法：

首先是所有的component都实现了receiveComponent来负责自己的更新，而浏览器默认元素的更新最为复杂，也就是经常说的 diff algorithm。react有一个全局_shouldUpdateReactComponent用来根据element的key来判断是更新还是重新渲染，这是第一个差异判断。比如自定义元素里，就使用这个判断，通过这种标识判断，会变得特别高效。每个类型的元素都要处理好自己的更新：

1. 自定义元素的更新，主要是更新render出的节点，做甩手掌柜交给render出的节点的对应component去管理更新。
2. text节点的更新很简单，直接更新文案。
3. 浏览器基本元素的更新，分为两块：

    先是更新属性，对比出前后属性的不同，局部更新。并且处理特殊属性，比如事件绑定。

    然后是子节点的更新，子节点更新主要是找出差异对象，找差异对象的时候也会使用上面的_shouldUpdateReactComponent来判断，如果是可以直接更新的就会递归调用子节点的更新，这样也会递归查找差异对象，这里还会使用lastIndex这种做一种优化，使一些节点保留位置，之后根据差异对象操作dom元素（位置变动，删除，添加等）。

整个reactjs的差异算法就是这个样子。最核心的两个_shouldUpdateReactComponent以及diff,patch算法。


