---
author: Ron
catalog: false
date: 2016-09-05T15:00:00Z
header-img: img/post-bg-os-metro.jpg
tags:
- neo4j
title: Neo4j Internal
url: /2016/09/05/neo4j-internal/
---

Neo4j中数据是如何存储的
<!--more-->

# 电子书 #

[GraphDatabase](/attach/OreillyGraphDatabases.pdf)


# 存储结构 #

现在让我们来看看数据在Neo4j中是如何存储的:

> .db是主存储文件,不同存储类型(node,relation,label,property)对应会有，例如neostore.propertystore.db是属性的主存储文件

> .id主要保存最大ID(数组长度)可复用ID(删除过),节点ID对应存储文件数组下标，例如neostore.propertystore.db.id是属性的主存储文件

> 另外存储文件包含层次结构,一般几个文件配合完成一种类型存储  
neostore.propertystore.db是属性的主存储文件  
neostore.propertystore.db.index存储属性key的id(key编码保存)  
neostore.propertystore.db.index.keys存储id相关的字符串名,属性value如果不是基本型(string,array),对应分别存储到neostore.propertystore.db.strings和neostore.propertystore.db.arrays中


首先看看节点Node文件

主文件neostore.nodestore.db的格式(早期版本,后期版本node_id,relationship_id,property_id高位会保存在in_use字节)： 

> Node:in_use(byte)+next_rel_id(int)+next_prop_id(int)+labels(5)+extra(byte)

每一位的具体意义如下：

- in_use:1表示该节点被使用，0表示被删除
- next_rel_id(int):该节点下一个关系id
- next_prop_id(int):该节点下一个属性的id
- labels(5 Bytes) : 第10~14字节是node 的label field
- extra(1 Byte) : 第15字节是 extra , 目前只用到第 1 bit ，表示该node 是否 dense, 缺省的配置是 该 node 的 relationshiop 的数量超过 50 个，表示是 dense,会对关系分组(group), neostore.relationshipgroupstore.db 用来保存关系分组数据

另外neostore.nodestore.db.labels存储节点label信息


再看看Relation格式： 

> in_use+first_node+second_node+rel_type+first_prev_rel_id+first_next_rel_id+second_prev_rel_id+second_next_rel_id+next_prop_id

- in_use,next_prop_id:同上
- first_node:当前关系的起始节点
- second_node:当前关系的终止节点
- rel_type:关系类型
- first_prev_rel_id & first_next_rel_id:起始节点的前一个和后一个关系id
- second_prev_rel_id & second_next_rel_id:终止节点的前一个和后一个关系id

在这个例子中，A~E表示Node 的编号，R1~R7 表示 Relationship 编号，P1~P10 表示Property 的编号。

![](/img/node-relation-example.png)

> Node 的存储示例图如下,每个Node 保存了第1个Property 和 第1个Relationship：

![](/img/node-detail.png)

> 关系的存储示意图如下:

![](/img/relation-detail.png)


下面举一个图的遍历的例子：

- 从节点1开始，宽度优先遍历，其存储结构为：01 00000002 ffffffff
- 其下一个关系id是2，访问关系2：01 00000001 00000004  00000000   ffffffff 00000001   ffffffff ffffffff    ffffffff 得出node 1 -> node 4,同时下个关系是1
- 关系1： 01 00000001 00000003  00000000   00000002 00000000   00000003 ffffffff    ffffffff node1->node 3,node3 有其他关系，所以将node3存入队列，同时访问关系0
- 关系0：01 00000001 00000002  00000000   00000001 ffffffff   ffffffff ffffffff    ffffffff node1->node2，访问完成node1的所有关系，从队列中退出node3
- 用于上文相同的方法访问node3

最后结果如下：

```
(1)–[KNOWS,2]–>(4)
(1)–[KNOWS,1]–>(3)
(1)–[KNOWS,0]–>(2)
(1)–[KNOWS,1]–>(3)–[KNOWS,5]–>(7)
(1)–[KNOWS,1]–>(3)–[KNOWS,4]–>(6)
(1)–[KNOWS,1]–>(3)–[KNOWS,3]–>(5)
```
		

# 执行计划 #

Using the [Neo4j web-based console](http://console.neo4j.org/), we can get the results of each query in the detailed query results.

<iframe height="600" src="http://console.neo4j.org/?id=f71ux0" width="900"></iframe>

Graph Setup

```
create (Neo:Crew {name:'Neo'}), (Morpheus:Crew {name: 'Morpheus'}), (Trinity:Crew {name: 'Trinity'}), (Cypher:Crew:Matrix {name: 'Cypher'}), (Smith:Matrix {name: 'Agent Smith'}), (Architect:Matrix {name:'The Architect'}),
(Neo)-[:KNOWS]->(Morpheus), (Neo)-[:LOVES]->(Trinity), (Morpheus)-[:KNOWS]->(Trinity),
(Morpheus)-[:KNOWS]->(Cypher), (Cypher)-[:KNOWS]->(Smith), (Smith)-[:CODED_BY]->(Architect)
```

run a slightly more complex Cypher query, the execution plan shows the piping of operations.

```
 // Find Kenny's friends
MATCH (kenny:Person {name:"Kenny"})-[:FRIEND_OF]-(friends)
RETURN friends
```


```
Query Results


+-----------------------+
| friends               |
+-----------------------+
| Node[1]{name:"Adam"}  |
| Node[2]{name:"Greta"} |
+-----------------------+
2 rows
14 ms


Execution Plan


ColumnFilter
  |
  +Filter
    |
    +TraversalMatcher

+------------------+------+--------+-------------+--------------------------------------------+
|         Operator | Rows | DbHits | Identifiers |                                      Other |
+------------------+------+--------+-------------+--------------------------------------------+
|     ColumnFilter |    2 |      0 |             |                       keep columns friends |
|           Filter |    2 |     12 |             | Property(kenny,name(0)) == {  AUTOSTRING0} |
| TraversalMatcher |    6 |     13 |             |              friends,   UNNAMED37, friends |
+------------------+------+--------+-------------+--------------------------------------------+
```

> The execution plan for the query shows 3 operators: ColumnFilter, Filter, and TraversalMatcher.     
The ColumnFilter operation receives a row of data from the Filter operation and processes it by keeping only the identifier "friends", which is in the RETURN statement.  
The Filter operation also receives rows of data from its preceding operation, the TraversalMatcher, and applies a predicate to decide whether to pass that data row along to the next operation (the ColumnFilter) or to discard it.   
In the case of our query, the predicate is to filter nodes by applying the criteria for the identifier "kenny" with the property "name" that equals AUTOSTRING0, which will resolve to the token "Kenny" when the plan is executed.   
Finally the TraversalMatcher doesn't receive any rows of data, due to being the first operation, but generates new rows of data by searching the graph for the pattern specified in the MATCH clause.  
So you can see that the execution plan, as constructed from the Cypher query, operates bottom up. Patterns are found in the TraversalMatcher (a total of 6 rows), and then passed through the Filter, which only allows 2 through, and finally to the ColumnFilter, which only keeps the "friends" column specified in the RETURN clause.  
For detailed query tuning options, check the [tuning guide](http://neo4j.com/docs/developer-manual/current/cypher/#query-tuning)

