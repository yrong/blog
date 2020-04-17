---
author: Ron
catalog: true
date: 2016-10-12T18:00:00Z
tags:
- d3
- javascript
title: D3.js数据可视化
---

D3.js数据可视化
<!--more-->

> 基于 [D3.js](https://d3js.org/) ，编写 HTML、SVG 和 CSS 就能让你的数据变得生动起来，这是一个基于数据操作 DOM 的 JavaScript 库。

每一位 Web 开发者最应该学习的三个 JavaScript 库就是 jQuery、Underscore 和 D3。在学习它们的过程中，你将会从新的角度去思考如何写代码：jQuery 让你知道如何用尽量少的代码，尽可能多地操作 DOM；Underscore （或者称之为 lodash）用函数式的工具改变你写程序的方式；而 D3 给了你大量的操作数据的工具，以及图形化编程的思想。如果你还不了解 D3，请花一些时间看看[它的例子](https://github.com/mbostock/d3/wiki/Gallery)，体会一下 D3 能做到什么。


D3 有极高的灵活性，它是一个比较基础的可视化 js 库，api 和 jQuery 很像，可以把数据和 HTML 结构或者 SVG 文档对应起来。D3 有丰富的数学函数来处理数据转换和物理计算，它擅长于操作 SVG 中的路径 (path) 和几何图形 (circle, ellipse, rect...)。

在接下来的例子里，你会看到输入的数据、数据变换和最后的输出文档。我将不会解释逐个函数做了什么，我会把代码展示给你看，希望从中你能知道大致这些代码是怎么工作的。只有在 [Scales](https://github.com/d3/d3-3.x-api-reference/blob/master/Scales.md) 和 [Selections](https://github.com/d3/d3-3.x-api-reference/blob/master/Selections.md) 的部分我才会重点解释。

## 柱状图

![](/images/learn-to-d3/01.png)
（[codepen 中查看代码](http://codepen.io/SitePoint/pen/wWJXWa)）

我说过在 D3 中，你能使用到的图表远比 Playfair 先生发明过的要多，但是学跑前先走好路，我们从最简单的柱状图开始，了解一下 D3 是怎么将数据和文档流结合在一起的：

```javascript
d3.select('#chart')
  .selectAll("div")
  .data([4, 8, 15, 16, 23, 42])
  .enter()
  .append("div")
  .style("height", (d)=> d + "px")
```

```selectAll``` 方法返回了一个 D3 selection。D3 selection 是一个数组，当针对一个数据点创建一个 ```div``` ，然后通过 ```enter()``` 和 ```append()``` 调用这个 ```div``` 时，selection 中的元素就会被创建出来。

上述代码中的输入数据是一组数组：[4, 8, 15, 16, 23, 42]，对应的输出 HTML 结构是：

``` html
<div id="chart">
  <div style="height: 4px;"></div>
  <div style="height: 8px;"></div>
  <div style="height: 15px;"></div>
  <div style="height: 16px;"></div>
  <div style="height: 23px;"></div>
  <div style="height: 42px;"></div>
</div>
```

所有不需要通过 JS 控制的视觉层内容都写到 CSS 中：

``` css
#chart div {
  display: inline-block;
  background: #4285F4;
  width: 20px;
  margin-right: 3px;
}
```

## GitHub 贡献表

只需要更改柱状图代码中的几行，我们就能得到一个 GitHub 贡献表。

![](/images/learn-to-d3/02.png)

（[codepen 中查看代码](http://codepen.io/SitePoint/pen/rLyKLG)）

和柱状图不同地方在于，图表中根据数据变化的不再是元素的高度，而是元素的 ```background-color``` （背景色）。

```javascript
const colorMap = d3.interpolateRgb(
  d3.rgb('#d6e685'),
  d3.rgb('#1e6823')
)

d3.select('#chart')
  .selectAll("div")
  .data([.2, .4, 0, 0, .13, .92])
  .enter()
  .append("div")
  .style("background-color", (d)=> {
    return d == 0 ? '#eee' : colorMap(d)
  })
```

```colorMap``` 函数接收的输入值要在0到1之间，返回的是一个颜色值，这个值是在以输入值中两两数据为颜色值之间的渐变色值。插值法是图形编程和动画的关键点。在后面我们将会看到更多这方面的例子。

## SVG

D3 最大的魅力大概来自于它能应用在 SVG 上，也就是说平面图形比如圆形、多边形、路径和文本，它都可以交互。

![](/images/learn-to-d3/03.png)

```html
<svg width="200" height="200">
  <circle fill="#3E5693" cx="50" cy="120" r="20" />
  <text x="100" y="100">Hello SVG!</text>
  <path d="M100,10L150,70L50,70Z" fill="#BEDBC3" stroke="#539E91" stroke-width="3">
</svg>
```

上述代码实现的是：

- 一个圆心在 (50,120)，半径是 20 的圆形
- 一段位于 (100,100) 的文本
- 一个 3px 粗边的三角形，```d``` 指的是方向，从点 (100,100) 画线到点 (150,170) 再到点 (50,70) 结束

```<path>``` 可以算是 SVG 中最好用的元素了。

## Circles

## 圆形

![](/images/learn-to-d3/04.png)

（[codepen 中查看代码](http://codepen.io/SitePoint/pen/jrBKMM)）

上面的例子中给出的数据结构是很简单的一组数据，D3 的能力远不止于此，它还可以操作更复杂的数据类型。

```javascript
const data = [{
  label: "7am",
  sales: 20
},{
  label: "8am",
  sales: 12
}, {
  label: "9am",
  sales: 8
}, {
  label: "10am",
  sales: 27
}]
```

对每一个数据点，我们都将有一个 ```g``` （组）元素在 ```#chart``` 中，根据对象的属性，每个组里会有一个 ```<circle>``` 元素和一个 ```<text>``` 元素。

下面的代码将输入数据和 SVG 文档一一对应起来，你能看出它的原理吗？

```html
<svg height="100" width="250" id="chart">
  <g>
    <circle cy="40" cx="50" r="20"/>
    <text y="90" x="50">7am</text>
  </g>
  <g>
    <circle cy="40" cx="100" r="12"/>
    <text y="90" x="100">8am</text>
  </g>
  <g>
    <circle cy="40" cx="150" r="8"/>
    <text y="90" x="150">9am</text>
  </g>
  <g>
    <circle cy="40" cx="200" r="27"/>
    <text y="90" x="200">10am</text>
  </g>
</svg>
```

## 折线图

![](/images/learn-to-d3/05.png)

（[codepen 中查看代码](http://codepen.io/SitePoint/pen/pbeKER)）

用 SVG 实现折线图再简单不过，我们将下面这些数据：

```javascript
const data = [
  { x: 0, y: 30 },
  { x: 50, y: 20 },
  { x: 100, y: 40 },
  { x: 150, y: 80 },
  { x: 200, y: 95 }
]
```

转换成以下的 SVG 文档：

```html
<svg id="chart" height="100" width="200">
  <path stroke-width="2" d="M0,70L50,80L100,60L150,20L200,5">
</svg>
```

**注意：** SVG 代码中的  ```y``` 值和输入值的 ```y``` 值不同，是用 100 减去给定的 ```y``` 值，因为在 SVG 中屏幕的左上角是 (0,0)，所以在纵坐标最大值是 100 的坐标系中，需要这么处理。

可以这么实现只由一条 ```path``` 构成的图形：

```javascript
const path = "M" + data.map((d)=> {
  return d.x + ',' + (100 - d.y);
}).join('L');
const line = `<path stroke-width="2" d="${ path }"/>`;
document.querySelector('#chart').innerHTML = line;
```

上面的代码看着可麻烦了，D3 其实提供了路径生成函数来简化这个步骤：

```javascript
const line = d3.svg.line()
  .x((d)=> d.x)
  .y((d)=> 100 - d.y)
  .interpolate("linear")

d3.select('#chart')
  .append("path")
  .attr('stroke-width', 2)
  .attr('d', line(data))
```

清爽多了！```interpolate``` 函数可接受不同的参数，画出不一样的图形，除了 'linear'，还可以试试看 'basis'、'cardinal'...

![](/images/learn-to-d3/06.png)

## Scales

> Scales 函数可以将一个输入集映射到一个输出集中。

[codepen 中查看代码](http://codepen.io/SitePoint/pen/aZJKmG)

上述例子所用的数据都是假数据，不会超过坐标轴所设定的范围。当数据是动态变化的时候，事情可就没有这么简单了，你需要将输入映射到固定范围的输出中，也就是我们的坐标轴。

假设我们有一个 500px X 200px 大小的折线图区域，输入数据是：

```javascript
const data = [
  { x: 0, y: 30 },
  { x: 25, y: 15 },
  { x: 50, y: 20 }
]
```

如果 y 轴的范围在 [0,30]，x 轴的范围在 [0,50]，那数据就能被漂亮地呈现在屏幕上。不过现实是，y 轴范围在0到200，x 轴范围在0到500间。

我们可以用 ```d3.max``` 获取到输入数据中的最大的 x 值和 y 值，然后创建出对应的 scales。

scale 和上面用到的颜色差值函数类似，都是将输入值对应到固定的输出范围中。

```javascript
xScale(0) -> 0
xScale(10) -> 100
xScale(50) -> 500
```

对于超出输出值范围的输入值，同样适用：

```javascript
xScale(-10) -> -100
xScale(60) -> 600
```

在生成折线图的代码中 scale 可以这么使用：

```javascript
const line = d3.svg.line()
  .x((d)=> xScale(d.x))
  .y((d)=> yScale(d.y))
  .interpolate("linear")
```

scales 还能让图形更优雅地显示出来，比如加上一点间距：

```javascript
const padding = 20;
const xScale = d3.scale.linear()
  .domain([0, xMax])
  .range([padding, width - padding])

const yScale = d3.scale.linear()
  .domain([0, yMax])
  .range([height - padding, padding])
```

现在可以在有动态数据集的前提下生成该集的折线图，这条折线图保证会在 500px X 200px 的范围内，并且距离该区域的四边都有 20px 的间距。

线性的 scale 最常见，不过还有处理指数的 pow、处理非数值数据（比如分类、命名等）的 ordinal scales，除此之外还有 [quantitative scales](https://github.com/mbostock/d3/wiki/Quantitative-Scales)、[ordinal scales](https://github.com/mbostock/d3/wiki/Ordinal-Scales) 和 [time scales](https://github.com/mbostock/d3/wiki/Time-Scales)。

比如把我的寿命当做输入值，映射到 [0,500] 的区域内：

```javascript
const life = d3.time.scale()
  .domain([new Date(1986, 1, 18), new Date()])
  .range([0, 500])

// 0 到 500 之间的哪个点才是我的 18 岁生日呢？
life(new Date(2004, 1, 18))
```

## 航线数据可视化

到目前为止，我们看到的都是静止的图像。接下来，以墨尔本到悉尼的航线为例，试试动态图像吧。

[codepen 中查看效果](http://codepen.io/SitePoint/pen/wWJXoK)

上面的效果是基于 SVG 的文本 (text)、线条 (line) 和圆形 (circle)。

```html
<svg id="chart" width="600" height="500">
  <text class="time" x="300" y="50" text-anchor="middle">6:00</text>
  <text class="origin-text" x="90" y="75" text-anchor="end">MEL</text>
  <text class="dest-text" x="510" y="75" text-anchor="start">SYD</text>
  <circle class="origin-dot" r="5" cx="100" cy="75" />
  <circle class="dest-dot" r="5" cx="500" cy="75" />
  <line class="origin-dest-line" x1="110" y1="75" x2="490" y2="75" />

  <!-- for each flight in the current time -->
  <g class="flight">
    <text class="flight-id" x="160" y="100">JQ 500</text>
    <line class="flight-line" x1="100" y1="100" x2="150" y2="100" />
    <circle class="flight-dot" cx="150" cy="100" r="5" />
  </g>
</svg>
```

动态变化的部分是时间和不同的航班，数据源大概长这样：

```javascript
let data = [
  { departs: '06:00 am', arrives: '07:25 am', id: 'Jetstar 500' },
  { departs: '06:00 am', arrives: '07:25 am', id: 'Qantas 400' },
  { departs: '06:00 am', arrives: '07:25 am', id: 'Virgin 803' }
]
```

我们需要将每条航线的出发和到达时间用 scale 映射到 x 轴上，这些数据将会动态地变化。在代码开始的位置，就将这些数据依次设定为 ```Date``` 对象，并 scale 它们，后面方便使用。对日期的处理我用的是 Moment.js。

```javascript
data.forEach((d)=> {
  d.departureDate = moment(d.departs, "hh-mm a").toDate();
  d.arrivalDate = moment(d.arrives, "hh-mm a").toDate();
  d.xScale = d3.time.scale()
    .domain([departureDate, arrivalDate])
    .range([100, 500])
});
```

现在可以把数据传入 ```xScale()``` 获取到每条航线的 x 坐标。

## 渲染循环

出发和到达时间都四舍五入到 5 分钟，所以在第一个航班起飞时间和最后一个航班到达时间之间以 5分钟为单位递增。

```javascript
let now = moment(data[0].departs, "hh:mm a");
const end = moment(data[data.length - 1].arrives, "hh:mm a");

const loop = function() {
  const time = now.toDate();

  // 选出当前的航班
  const currentData = data.filter((d)=> {
    return d.departureDate <= time && time <= d.arrivalDate
  });

  render(currentData, time);

  if (now <= end) {
    // Increment 5m and call loop again in 500ms
    // 5分钟为增量，500ms 轮询依次
    now = now.add(5, 'minutes');
    setTimeout(loop, 500);
  }
}
```

## 创建、更新和过期

在以下场景下，开发者可以指定要使用的数据变换和元素过渡方式：

+ 新数据点出现的时候（创建时）
+ 现有的数据发生变化（更新时）
+ 数据不再使用时（过期时）

```javascript
const render = function(data, time) {
  // 渲染 'time'
  d3.select('.time')
    .text(moment(time).format("hh:mm a"))

  // 创建 selection，传入数据集
  const flight = d3.select('#chart')
    .selectAll('g.flight')
    .data(data, (d)=> d.id)

  // 为新的数据创建节点
  const newFlight = flight.enter()
    .append("g")
    .attr('class', 'flight')

  const xPoint = (d)=> d.xScale(time);
  const yPoint = (d, i)=> 100 + i * 25;

  newFlight.append("circle")
    .attr('class',"flight-dot")
    .attr('cx', xPoint)
    .attr('cy', yPoint)
    .attr('r', "5")

  // 通过 select 更新现有的数据
  flight.select('.flight-dot')
    .attr('cx', xPoint)
    .attr('cy', yPoint)

  // 移除不需要的数据
  const oldFlight = flight.exit()
    .remove()
}
```

## 过渡

上述的代码实现了每 500ms 以 5 分钟为增量渲染画面：

+ 更新了时间
+ 每当有新的航班图时，以圆为标识创建
+ 更新当前航班的 x/y 坐标轴
+ 当飞机到达目的地时，移除数据

可以说已经实现了我们开始时的目标，但是每次新数据的出现和旧数据的销毁都太粗暴。通过在 D3 selection 上添加过渡，就能把这个过程变得平滑。

比如，为新数据添加到 DOM 结构中，通过改变透明度 (opacity)，加一个渐现动画：

```javascript
const newFlight = flight.enter()
  .append("g")
  .attr('class', 'flight')
  .attr('opacity', 0)

newFlight.transition()
  .duration(500)
  .attr('opacity', 1)
```

数据移除可以加上渐隐动画：

```javascript
flight.exit()
  .transition()
  .duration(500)
  .attr('opacity', 0)
  .remove()
```

在横纵坐标点上也可以加上：

```javascript
flight.select('.flight-dot')
  .transition()
  .duration(500)
  .ease('linear')
  .attr('cx', xPoint)
  .attr('cy', yPoint)
```

我们也能对这 5 分钟的增量做过渡，用 ```tween``` 函数实现每分钟时间都将出现，而不是每 5 分钟才会出现。


```javascript
const inFiveMinutes = moment(time).add(5, 'minutes').toDate();
const i = d3.interpolate(time, inFiveMinutes);
d3.select('.time')
  .transition()
  .duration(500)
  .ease('linear')
  .tween("text", ()=> {
    return function(t) {
      this.textContent = moment(i(t)).format("hh:mm a");
    };
  });
```

```t``` 是用于变换的一个介于 0 到 1 的增长值。

## 树形图



![](/blog/images/learn-to-d3/tree-02.png)

```
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">

    <title>Tree Example</title>

    <style>
  
  .node {
    cursor: pointer;
  }
  .node circle {
    fill: #fff;
    stroke: steelblue;
    stroke-width: 3px;
  }
  .node text {
    font: 12px sans-serif;
  }
  .link {
    fill: none;
    stroke: #ccc;
    stroke-width: 2px;
  }
  
    </style>

  </head>

  <body>

<!-- load the d3.js library --> 
<script src="http://d3js.org/d3.v3.min.js"></script>
  
<script>
var treeData = [
  {
    "name": "Top Level",
    "parent": "null",
    "children": [
      {
        "name": "Level 2: A",
        "parent": "Top Level",
        "children": [
          {
            "name": "Son of A",
            "parent": "Level 2: A"
          },
          {
            "name": "Daughter of A",
            "parent": "Level 2: A"
          }
        ]
      },
      {
        "name": "Level 2: B",
        "parent": "Top Level"
      }
    ]
  }
];
// ************** Generate the tree diagram  *****************
var margin = {top: 20, right: 120, bottom: 20, left: 120},
  width = 960 - margin.right - margin.left,
  height = 500 - margin.top - margin.bottom;
  
var i = 0,
  duration = 750,
  root;
var tree = d3.layout.tree()
  .size([height, width]);
var diagonal = d3.svg.diagonal()
  .projection(function(d) { return [d.y, d.x]; });
var svg = d3.select("body").append("svg")
  .attr("width", width + margin.right + margin.left)
  .attr("height", height + margin.top + margin.bottom)
  .append("g")
  .attr("transform", "translate(" + margin.left + "," + margin.top + ")");
root = treeData[0];
root.x0 = height / 2;
root.y0 = 0;
  
update(root);
d3.select(self.frameElement).style("height", "500px");
function update(source) {
  // Compute the new tree layout.
  var nodes = tree.nodes(root).reverse(),
    links = tree.links(nodes);
  // Normalize for fixed-depth.
  nodes.forEach(function(d) { d.y = d.depth * 180; });
  // Update the nodes…
  var node = svg.selectAll("g.node")
    .data(nodes, function(d) { return d.id || (d.id = ++i); });
  // Enter any new nodes at the parent's previous position.
  var nodeEnter = node.enter().append("g")
    .attr("class", "node")
    .attr("transform", function(d) { return "translate(" + source.y0 + "," + source.x0 + ")"; })
    .on("click", click);
  nodeEnter.append("circle")
    .attr("r", 1e-6)
    .style("fill", function(d) { return d._children ? "lightsteelblue" : "#fff"; });
  nodeEnter.append("text")
    .attr("x", function(d) { return d.children || d._children ? -13 : 13; })
    .attr("dy", ".35em")
    .attr("text-anchor", function(d) { return d.children || d._children ? "end" : "start"; })
    .text(function(d) { return d.name; })
    .style("fill-opacity", 1e-6);
  // Transition nodes to their new position.
  var nodeUpdate = node.transition()
    .duration(duration)
    .attr("transform", function(d) { return "translate(" + d.y + "," + d.x + ")"; });
  nodeUpdate.select("circle")
    .attr("r", 10)
    .style("fill", function(d) { return d._children ? "lightsteelblue" : "#fff"; });
  nodeUpdate.select("text")
    .style("fill-opacity", 1);
  // Transition exiting nodes to the parent's new position.
  var nodeExit = node.exit().transition()
    .duration(duration)
    .attr("transform", function(d) { return "translate(" + source.y + "," + source.x + ")"; })
    .remove();
  nodeExit.select("circle")
    .attr("r", 1e-6);
  nodeExit.select("text")
    .style("fill-opacity", 1e-6);
  // Update the links…
  var link = svg.selectAll("path.link")
    .data(links, function(d) { return d.target.id; });
  // Enter any new links at the parent's previous position.
  link.enter().insert("path", "g")
    .attr("class", "link")
    .attr("d", function(d) {
    var o = {x: source.x0, y: source.y0};
    return diagonal({source: o, target: o});
    });
  // Transition links to their new position.
  link.transition()
    .duration(duration)
    .attr("d", diagonal);
  // Transition exiting nodes to the parent's new position.
  link.exit().transition()
    .duration(duration)
    .attr("d", function(d) {
    var o = {x: source.x, y: source.y};
    return diagonal({source: o, target: o});
    })
    .remove();
  // Stash the old positions for transition.
  nodes.forEach(function(d) {
  d.x0 = d.x;
  d.y0 = d.y;
  });
}
// Toggle children on click.
function click(d) {
  if (d.children) {
  d._children = d.children;
  d.children = null;
  } else {
  d.children = d._children;
  d._children = null;
  }
  update(d);
}
</script>
  
  </body>
</html>

```

### 关键代码注解 ###

```
var diagonal = d3.svg.diagonal()
 .projection(function(d) { return [d.y, d.x]; });
```
声明[d3.js diagonal](https://github.com/d3/d3-3.x-api-reference/blob/master/SVG-Shapes.md)连接线发生器,注意这里x,y坐标系互换


```
var nodes = tree.nodes(root),
   links = tree.links(nodes);

```
treenode和links的初始化,参见[树布局](https://github.com/d3/d3/wiki/%E6%A0%91%E5%B8%83%E5%B1%80),每个节点中包含以下属性：

- parent - 父节点引用，根节点为 null;
- children - 所有子节点，叶子节点为 null;
- depth - 当前节点所处层级（也叫深度）；根节点为 0;
- x - 计算得到的当前节点的计 x 坐标;
- y - 计算得到的当前节点的计 y 坐标;


```
  nodes.forEach(function(d) { d.y = d.depth * 180; });
```

定义节点深度(level)和水平(x,y坐标系已互换)位置的关系.

![](/blog/images/learn-to-d3/tree-05.png)


```
var node = svg.selectAll("g.node")
   .data(nodes, function(d) { return d.id || (d.id = ++i); });

var link = svg.selectAll("path.link")
   .data(links, function(d) { return d.target.id; });
   .enter().insert("path", "g")
   .attr("class", "link")
   .attr("d", diagonal);
```
根据生成的节点id关联链路,用diagonal产生连接曲线


```
.node {
  cursor: pointer;
 }


function click(d) {
  if (d.children) {
 d._children = d.children;
 d.children = null;
  } else {
 d.children = d._children;
 d._children = null;
  }
  update(d);
}
```
根据children属性添加交互式collapse效果(点击根节点隐藏子节点,再点展开)



## 地图

用不同颜色标注你所去过的地方

```
<!DOCTYPE html>
<meta charset="utf-8">
<style>

/* CSS goes here. */

</style>
<body>
<div id="chart" style="max-width: 47.5em; margin: 10px auto; position: relative;">
<script src="//d3js.org/d3.v3.min.js" charset="utf-8"></script>
<script src="//d3js.org/topojson.v1.min.js"></script>
<script>
  var width  = 700;
  var height = 400;

  var myMap = new Map();
      myMap.set("甘肃", "#F5A9A9");
      myMap.set("青海", "#F5A9A9");
      myMap.set("广西", "#A4A4A4");
      myMap.set("贵州", "#F5A9A9");
      myMap.set("重庆", "#F5A9A9");
      myMap.set("北京", "#FA5858");
      myMap.set("福建", "#A4A4A4");
      myMap.set("安徽", "#A4A4A4");
      myMap.set("广东", "#A4A4A4");
      myMap.set("西藏", "#A4A4A4");
      myMap.set("新疆", "#A4A4A4");
      myMap.set("海南", "#F5A9A9");
      myMap.set("宁夏", "#A4A4A4");
      myMap.set("陕西", "#F5A9A9");
      myMap.set("山西", "#A4A4A4");
      myMap.set("湖北", "#FA5858");
      myMap.set("湖南", "#F5A9A9");
      myMap.set("四川", "#FE2E2E");
      myMap.set("云南", "#A4A4A4");
      myMap.set("河北", "#F5A9A9");
      myMap.set("河南", "#A4A4A4");
      myMap.set("辽宁", "#A4A4A4");
      myMap.set("山东", "#A4A4A4");
      myMap.set("天津", "#A4A4A4");
      myMap.set("江西", "#A4A4A4");
      myMap.set("江苏", "#FA5858");
      myMap.set("上海", "#FA5858");
      myMap.set("浙江", "#F5A9A9");
      myMap.set("吉林", "#A4A4A4");
      myMap.set("内蒙古", "#A4A4A4");
      myMap.set("黑龙江", "#A4A4A4");
      myMap.set("香港", "#F5A9A9");
      myMap.set("澳门", "#A4A4A4");
      myMap.set("台湾", "#A4A4A4");
      myMap.set("background", "#2A0A0A");
  
  var svg = d3.select("#chart").append("svg")
    .attr("width", '100%')
    .attr("height", '100%')
    .attr('viewBox','0 0 '+(Math.min(width,height))+' '+Math.min(width,height))
    .attr('preserveAspectRatio','xMinYMin')
      .append("g")
      .attr("transform", "translate(0,0)");
  
  var projection = d3.geo.mercator()
            .center([107, 31])
            .scale(350)
              .translate([width/2-130, height/2+30]);
  
  var path = d3.geo.path()
          .projection(projection);
  
  d3.json("china_simplify.json", function(error, root) {
    
    if (error) 
      return console.error(error);
    console.log(root.features);
    
    svg.selectAll("path")
      .data( root.features )
      .enter()
      .append("path")
      .attr("stroke","#000")
      .attr("stroke-width",1)
      .attr("fill", function(d,i){
        return myMap.get("background");
      })
      .attr("d", path )
      .on("mouseover",function(d,i){
                d3.select(this)
                    .attr("fill","#ACB1E6");
            })
            .on("mouseout",function(d,i){
                d3.select(this)
                    .attr("fill",myMap.get(d.properties.name));
            });
    
  });

</script>
</div>
</body>

```

### 关键代码注解 ###

Define your projection

```
    var projection = d3.geo.mercator()
            .center([107, 31]) //(107,31) as center
            .scale(350)
              .translate([width/2-130, height/2+30]);// centers in SVG
```

When you define a projection, you tell D3 how to transform your data from spherical to Cartesian coordinates. Take a look at the projection docs to get a sense of how you can project your data with D3.

Translate to screen coordinates

```
    var path = d3.geo.path()
          .projection(projection);
```

When D3 renders your SVG, it has to translate geo coordinates to pixel coordinates on your screen. This functionality is called a path generator. In this block, we store our path generator in the variable path so we can access it through out our code.

Load geo json data

```
d3.json("china_simplify.json", function(error, root) { // loads JSON file
    
    if (error) 
      return console.error(error);
    console.log(root.features);
    
    svg.selectAll("path") // selects path elements, will make them if they don't exist
      .data( root.features ) // iterates over geo feature
      .enter() // adds feature if it doesn't exist as an element
      .append("path") // defines element as a path
      .attr("stroke","#000")
      .attr("stroke-width",1)
      .attr("fill", function(d,i){
        return myMap.get("background");
      })
      .attr("d", path )  // path generator translates geo data to SVG
      .on("mouseover",function(d,i){
                d3.select(this)
                    .attr("fill","#ACB1E6");
            })
            .on("mouseout",function(d,i){
                d3.select(this)
                    .attr("fill",myMap.get(d.properties.name));
            });
    
  });

```

## Neo4j Link Graph Render ##

visualization toolkits usually expect a JSON structure of node objects (their id, label(s) and properties) and a list of relationships (their properties, start- and end-node-id (or node-array-index for d3) and optionally relationship-id) like this. Here we see 3 nodes (2 people, one database) and 3 relationships in that datastructure.

> Target JSON DataStructure

```
{"nodes":[{name:"Peter",label:"Person",id:1},{name:"Michael",label:"Person",id:2},
          {name:"Neo4j",label:"Database",id:3}],
 "links":[{source:0, target:1, type:"KNOWS", since:2010},{source:0, target:2, type:"FOUNDED"},
          {source:1, target:2, type:"WORKS_ON"}]}
```

> neo4j Query Result DataStructure

```
{ "results": [
    {
      "columns": ["path"],
      "data"   : [{
          "graph": {
            "nodes": [
              {"id": "1", "labels": ["Person"], "properties": {"name": "Peter"}},
              {"id": "2", "labels": ["Person"], "properties": {"name": "Michael"}}
             ],
            "relationships": [
              {"id": "0", "type": "KNOWS", "startNode": "1", "endNode": "2", "properties": {}}
             ]
          } // , {"graph": ...}, ...
      }]}
  ], "errors": []
}
```

> conversion logic

``` js
function idIndex(a,id) {
  for (var i=0;i<a.length;i++) {
    if (a[i].id == id) return i;}
  return null;
}
var nodes=[], links=[];
res.results[0].data.forEach(function (row) {
   row.graph.nodes.forEach(function (n) {
     if (idIndex(nodes,n.id) == null)
       nodes.push({id:n.id,label:n.labels[0],title:n.properties.name});
   });
   links = links.concat( row.graph.relationships.map(function(r) {
     return {source:idIndex(nodes,r.startNode),target:idIndex(nodes,r.endNode),type:r.type};
   }));
});
viz = {nodes:nodes, links:links};
```

``` python
results = db.run("MATCH (m:Movie)<-[:ACTED_IN]-(a:Person) "
         "RETURN m.title as movie, collect(a.name) as cast "
         "LIMIT {limit}", {"limit": request.args.get("limit", 100)})
nodes = []
rels = []
i = 0
for record in results:
    nodes.append({"title": record["movie"], "label": "movie"})
    target = i
    i += 1
    for name in record['cast']:
        actor = {"title": name, "label": "actor"}
        try:
            source = nodes.index(actor)
        except ValueError:
            nodes.append(actor)
            source = i
            i += 1
        rels.append({"source": source, "target": target})
```

To render this list with D3, you just need the d3.js library dependency and a few lines of javascript.

```
var width = 800, height = 800;
  // force layout setup
  var force = d3.layout.force()
          .charge(-200).linkDistance(30).size([width, height]);

  // setup svg div
  var svg = d3.select("#graph").append("svg")
          .attr("width", "100%").attr("height", "100%")
          .attr("pointer-events", "all");

  // load graph (nodes,links) json from /graph endpoint
  d3.json("/graph", function(error, graph) {
if (error) return;

      force.nodes(graph.nodes).links(graph.links).start();

      // render relationships as lines
      var link = svg.selectAll(".link")
              .data(graph.links).enter()
              .append("line").attr("class", "link");

      // render nodes as circles, css-class from label
      var node = svg.selectAll(".node")
              .data(graph.nodes).enter()
              .append("circle")
              .attr("class", function (d) { return "node "+d.label })
              .attr("r", 10)
              .call(force.drag);

      // html title attribute for title node-attribute
      node.append("title")
              .text(function (d) { return d.title; })

      // force feed algo ticks for coordinate computation
      force.on("tick", function() {
          link.attr("x1", function(d) { return d.source.x; })
                  .attr("y1", function(d) { return d.source.y; })
                  .attr("x2", function(d) { return d.target.x; })
                  .attr("y2", function(d) { return d.target.y; });

          node.attr("cx", function(d) { return d.x; })
                  .attr("cy", function(d) { return d.y; });
      });
  });
```

[my example project](https://github.com/yrong/movies-python-bolt)

## Others

D3 能做的事太多，不一一讲解了。

+ [极地时钟](http://bl.ocks.org/mbostock/1096355)
+ [Force Layouts](http://bl.ocks.org/mbostock/4062045)
+ [世界地图](http://bl.ocks.org/mbostock/4060606) & [3D 地球](http://bl.ocks.org/mbostock/3757125)
+ [Voronoi Tessellation](http://bl.ocks.org/mbostock/4060366)
+ [Prim’s Algorithm V](http://bl.ocks.org/mbostock/aa7edeac67253ea5de7f)
+ [OMG Particles II](http://bl.ocks.org/mbostock/9539958)

在 [D3 Gallery](https://github.com/d3/d3/wiki/Gallery) 中能找到更多例子。推荐 [Scott Murray 的 D3 教程](http://alignedleft.com/tutorials/d3/)和 [D3 的官方文档](https://github.com/d3/d3-3.x-api-reference/blob/master/API-Reference.md)。
