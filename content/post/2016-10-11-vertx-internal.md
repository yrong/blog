---
author: Ron
catalog: false
date: 2016-10-11T18:00:00Z
tags:
- vertx
title: vertx源码分析
---

vertx源码分析
<!--more-->

## Cluster初始化 ##

调用Vertx.clusteredVertx静态方法后，Vert.x会利用Vertx工厂方法创建Vertx实例。

~~~java
@Override
public void clusteredVertx(VertxOptions options, final Handler<AsyncResult<Vertx>> resultHandler) {
  // We don't require the user to set clustered to true if they use this method
  options.setClustered(true);
  new VertxImpl(options, resultHandler);
}
~~~

在VertxImpl的构造方法中，若需要创建集群，则执行：

~~~java
...
if (options.isClustered()) {
  this.clusterManager = getClusterManager(options);
  this.clusterManager.setVertx(this);
  this.clusterManager.join(ar -> {
    if (ar.failed()) {
      log.error("Failed to join cluster", ar.cause());
    } else {
      // Provide a memory barrier as we are setting from a different thread
      synchronized (VertxImpl.this) {
        haManager = new HAManager(this, deploymentManager, clusterManager, options.getQuorumSize(),
                                  options.getHAGroup(), haEnabled);
        createAndStartEventBus(options, resultHandler);
      }
    }
  });
}
~~~

获取集群的配置管理实例

~~~java
private ClusterManager getClusterManager(VertxOptions options) {
    if (options.isClustered()) {
      if (options.getClusterManager() != null) {
        return options.getClusterManager();
      } else {
        ClusterManager mgr;
        String clusterManagerClassName = System.getProperty("vertx.cluster.managerClass");
        if (clusterManagerClassName != null) {
          // We allow specify a sys prop for the cluster manager factory which overrides ServiceLoader
          try {
            Class<?> clazz = Class.forName(clusterManagerClassName);
            mgr = (ClusterManager) clazz.newInstance();
          } catch (Exception e) {
            throw new IllegalStateException("Failed to instantiate " + clusterManagerClassName, e);
          }
        } else {
          mgr = ServiceHelper.loadFactoryOrNull(ClusterManager.class);
          if (mgr == null) {
            throw new IllegalStateException("No ClusterManagerFactory instances found on classpath");
          }
        }
        return mgr;
      }
    } else {
      return null;
    }
  }
~~~

因为缺省没有指定managerClass，则使用默认集群加载类启动集群

> ServiceLoader<ClusterManager> mgrs = ServiceLoader.load(ClusterManager.class); 

hazelcast cluster代码在单独的[repo](https://github.com/vert-x3/vertx-hazelcast)

> META-INF/services/io.vertx.core.spi.cluster.ClusterManager

指定了ClusterManager加载io.vertx.spi.cluster.hazelcast.HazelcastClusterManager,加入HazelcastCluster

~~~java
public synchronized void join(Handler<AsyncResult<Void>> resultHandler) {
    vertx.executeBlocking(fut -> {
      if (!active) {
        active = true;

        // The hazelcast instance has been passed using the constructor.
        if (customHazelcastCluster) {
          nodeID = hazelcast.getLocalEndpoint().getUuid();
          membershipListenerId = hazelcast.getCluster().addMembershipListener(this);
          fut.complete();
          return;
        }

        if (conf == null) {
          conf = loadConfig();
          if (conf == null) {
            log.warn("Cannot find cluster configuration on 'vertx.hazelcast.config' system property, on the classpath, " +
                "or specified programmatically. Using default hazelcast configuration");
          }
        }
        hazelcast = Hazelcast.newHazelcastInstance(conf);
        nodeID = hazelcast.getLocalEndpoint().getUuid();
        membershipListenerId = hazelcast.getCluster().addMembershipListener(this);
        fut.complete();
      }
    }, resultHandler);
  }
~~~

## EventBus初始化及消息收发流程 ##
  
### 初始化eventbus ###  

  VertxImpl在加入集群后初始化并启动eventbus

~~~java
  private void createAndStartEventBus(VertxOptions options, Handler<AsyncResult<Vertx>> resultHandler) {
    if (options.isClustered()) {
      eventBus = new ClusteredEventBus(this, options, clusterManager, haManager);
    } else {
      eventBus = new EventBusImpl(this);
    }
    eventBus.start(ar2 -> {
      if (ar2.succeeded()) {
        // If the metric provider wants to use the event bus, it cannot use it in its constructor as the event bus
        // may not be initialized yet. We invokes the eventBusInitialized so it can starts using the event bus.
        metrics.eventBusInitialized(eventBus);

        if (resultHandler != null) {
          resultHandler.handle(Future.succeededFuture(this));
        }
      } else {
        log.error("Failed to start event bus", ar2.cause());
      }
    });
  }

  @Override
  public void start(Handler<AsyncResult<Void>> resultHandler) {
    clusterManager.<String, ServerID>getAsyncMultiMap(SUBS_MAP_NAME, ar2 -> {
      if (ar2.succeeded()) {
        subs = ar2.result();
        server = vertx.createNetServer(getServerOptions());//建立一个NetServer接收数据

        server.connectHandler(getServerHandler());
        server.listen(asyncResult -> {
          if (asyncResult.succeeded()) {
            int serverPort = getClusterPublicPort(options, server.actualPort());
            String serverHost = getClusterPublicHost(options);
            serverID = new ServerID(serverPort, serverHost);
            haManager.addDataToAHAInfo(SERVER_ID_HA_KEY, new JsonObject().put("host", serverID.host).put("port", serverID.port));
            if (resultHandler != null) {
              started = true;
              resultHandler.handle(Future.succeededFuture());
            }
          } else {
            if (resultHandler != null) {
              resultHandler.handle(Future.failedFuture(asyncResult.cause()));
            } else {
              log.error(asyncResult.cause());
            }
          }
        });
      } else {
        if (resultHandler != null) {
          resultHandler.handle(Future.failedFuture(ar2.cause()));
        } else {
          log.error(ar2.cause());
        }
      }
    });
  }
~~~


### 注册监听 ###

~~~java
EventBus eb = vertx.eventBus();

eb.consumer("news.uk.sport", message -> {
  System.out.println("I have received a message: " + message.body());
});
~~~

包含本地和远程注册

~~~java
protected <T> void addRegistration(String address, HandlerRegistration<T> registration,
                                     boolean replyHandler, boolean localOnly) {
    Objects.requireNonNull(registration.getHandler(), "handler");
    boolean newAddress = addLocalRegistration(address, registration, replyHandler, localOnly);
    addRegistration(newAddress, address, replyHandler, localOnly, registration::setResult);
  }
~~~

本地注册

~~~java
protected <T> boolean addLocalRegistration(String address, HandlerRegistration<T> registration,
                                             boolean replyHandler, boolean localOnly) {
    Objects.requireNonNull(address, "address");

    Context context = Vertx.currentContext();
    boolean hasContext = context != null;
    if (!hasContext) {
      // Embedded
      context = vertx.getOrCreateContext();
    }
    registration.setHandlerContext(context);

    boolean newAddress = false;

    HandlerHolder holder = new HandlerHolder<>(metrics, registration, replyHandler, localOnly, context);

    Handlers handlers = handlerMap.get(address);
    if (handlers == null) {
      handlers = new Handlers();
      Handlers prevHandlers = handlerMap.putIfAbsent(address, handlers);
      if (prevHandlers != null) {
        handlers = prevHandlers;
      }
      newAddress = true;
    }
    handlers.list.add(holder);

    if (hasContext) {
      HandlerEntry entry = new HandlerEntry<>(address, registration);
      context.addCloseHook(entry);
    }

    return newAddress;
  }
~~~

远程Registering Handlers实质是在某个节点A给集群模式的Event Bus绑定一个对应地址address的consumer,绑定MessageConsumer

~~~java
@Override
protected <T> void addRegistration(boolean newAddress, String address,
                                   boolean replyHandler, boolean localOnly,
                                   Handler<AsyncResult<Void>> completionHandler) {
  if (newAddress && subs != null && !replyHandler && !localOnly) {
    //Event会将此节点的ServerID（包含host和port信息）存储至集群管理器(HazelcastClusterManager)的共享Map中，key为绑定的地址address，value为绑定了此地址address的所有结点的ServerID集合
    subs.add(address, serverID, completionHandler); 
  } else {
    completionHandler.handle(Future.succeededFuture());
  }
}
~~~


### 消息的send/publish ###

~~~java
eventBus.publish("news.uk.sport", "Yay! Someone kicked a ball");
eventBus.send("news.uk.sport", "Yay! Someone kicked a ball");
~~~

集群模式下的消息实体类型为ClusteredMessage，它继承了MessageImpl消息实体类，并且根据远程传输的特性实现了一种Wire Protocol用于远程传输消息，并负责消息的编码和解码。
ClusteredEventBus里通过createMessage方法创建消息

~~~java
@Override
protected MessageImpl createMessage(boolean send, String address, MultiMap headers, Object body, String codecName) {
  Objects.requireNonNull(address, "no null address accepted");
  MessageCodec codec = codecManager.lookupCodec(body, codecName);
  @SuppressWarnings("unchecked")
  ClusteredMessage msg = new ClusteredMessage(serverID, address, null, headers, body, codec, send, this);
  return msg;
}
~~~

接下来就是消息的发送逻辑了。ClusteredEventBus重写了sendOrPub方法，此方法存在于SendContextImpl类中的next方法:

~~~java
private <T> void sendOrPubInternal(MessageImpl message, DeliveryOptions options,
                                     Handler<AsyncResult<Message<T>>> replyHandler) {
    checkStarted();
    HandlerRegistration<T> replyHandlerRegistration = createReplyHandlerRegistration(message, options, replyHandler);
    SendContextImpl<T> sendContext = new SendContextImpl<>(message, options, replyHandlerRegistration);
    sendContext.next();
  }

@Override
public void next() {
  if (iter.hasNext()) {
    Handler<SendContext> handler = iter.next();
    try {
      handler.handle(this);
    } catch (Throwable t) {
      log.error("Failure in interceptor", t);
    }
  } else {
    sendOrPub(this);
  }
}
~~~


我们来看一下ClusteredEventBus是如何进行集群内消息的分发的：

~~~java
@Override
protected <T> void sendOrPub(SendContextImpl<T> sendContext) {
  String address = sendContext.message.address();
  Handler<AsyncResult<ChoosableIterable<ServerID>>> resultHandler = asyncResult -> {
    if (asyncResult.succeeded()) {
      ChoosableIterable<ServerID> serverIDs = asyncResult.result();
      if (serverIDs != null && !serverIDs.isEmpty()) {
        sendToSubs(serverIDs, sendContext);
      } else {
        metrics.messageSent(address, !sendContext.message.send(), true, false);
        deliverMessageLocally(sendContext);
      }
    } else {
      log.error("Failed to send message", asyncResult.cause());
    }
  };
  if (Vertx.currentContext() == null) {
    // Guarantees the order when there is no current context
    sendNoContext.runOnContext(v -> {
      subs.get(address, resultHandler);
    });
  } else {
    subs.get(address, resultHandler);
  }
}
~~~

首先Event Bus需要从传入的sendContext中获取要发送至的地址。接着Event Bus需要从集群管理器中获取在此地址上绑定consumer的所有ServerID，这个过程是异步的，并且需要在Vert.x Context中执行。如果获取记录成功，我们会得到一个可通过轮询算法获取ServerID的集合(类型为ChoosableIterable<ServerID>)。如果集合为空，则代表集群内其它节点没有在此地址绑定consumer（或者由于一致性问题没有同步），Event Bus就将消息通过deliverMessageLocally方法在本地进行相应的分发。如果集合不为空，Event Bus就调用sendToSubs方法进行下一步操作：

~~~java
private <T> void sendToSubs(ChoosableIterable<ServerID> subs, SendContextImpl<T> sendContext) {
  String address = sendContext.message.address();
  if (sendContext.message.send()) {
    // Choose one
    ServerID sid = subs.choose();
    if (!sid.equals(serverID)) {  //We don't send to this node
      metrics.messageSent(address, false, false, true);
      sendRemote(sid, sendContext.message);
    } else {
      metrics.messageSent(address, false, true, false);
      deliverMessageLocally(sendContext);
    }
  } else {
    // Publish
    boolean local = false;
    boolean remote = false;
    for (ServerID sid : subs) {
      if (!sid.equals(serverID)) {  //We don't send to this node
        remote = true;
        sendRemote(sid, sendContext.message);
      } else {
        local = true;
      }
    }
    metrics.messageSent(address, true, local, remote);
    if (local) {
      deliverMessageLocally(sendContext);
    }
  }
}
~~~
这里就到了分send和publish的时候了。如果发送消息的模式为点对点模式(send)，Event Bus会从给的的集合中通过轮询算法获取一个ServerID。然后Event Bus会检查获取到的ServerID是否与本机ServerID相同，如果相同则代表在一个机子上，直接记录metrics信息并且调用deliverMessageLocally方法往本地发送消息即可；如果不相同，Event Bus就会调用sendRemote方法执行真正的远程消息发送逻辑。发布订阅模式的逻辑与其大同小异，只不过需要遍历一下ChoosableIterable<ServerID>集合，然后依次执行之前讲过的逻辑。注意如果要在本地发布消息只需要发一次。

真正的远程消息发送逻辑在sendRemote方法中:

~~~java
private void sendRemote(ServerID theServerID, MessageImpl message) {
  ConnectionHolder holder = connections.get(theServerID);
  if (holder == null) {
    holder = new ConnectionHolder(this, theServerID, options);
    ConnectionHolder prevHolder = connections.putIfAbsent(theServerID, holder);
    if (prevHolder != null) {
      // Another one sneaked in
      holder = prevHolder;
    } else {
      holder.connect();
    }
  }
  holder.writeMessage((ClusteredMessage)message);
}
~~~

一开始我们就提到过，节点之间通过Event Bus进行通信的本质是TCP，因此这里需要创建一个NetClient作为TCP服务端，连接到之前获取的ServerID对应的节点然后将消息通过TCP协议发送至接收端。这里Vert.x用一个封装类ConnectionHolder对NetClient进行了一些封装。

ClusteredEventBus中维持着一个connections哈希表对用于保存ServerID对应的连接ConnectionHolder。在sendRemote方法中,Event Bus首先会从connections中获取ServerID对应的连接。如果获取不到就创建连接并将其添加至connections记录中并调用对应ConnectionHolder的connect方法建立连接；最后调用writeMessage方法将消息编码后通过TCP发送至对应的接收端。

那么ConnectionHolder是如何实现的呢？我们来看一下其构造函数：

~~~java
ConnectionHolder(ClusteredEventBus eventBus, ServerID serverID, EventBusOptions options) {
  this.eventBus = eventBus;
  this.serverID = serverID;
  this.vertx = eventBus.vertx();
  this.metrics = eventBus.getMetrics();
  NetClientOptions clientOptions = new NetClientOptions(options.toJson());
  ClusteredEventBus.setCertOptions(clientOptions, options.getKeyCertOptions());
  ClusteredEventBus.setTrustOptions(clientOptions, options.getTrustOptions());
  client = new NetClientImpl(eventBus.vertx(), clientOptions, false);
}
~~~

可以看到ConnectionHolder初始化的时候会创建一个NetClient作为TCP请求端，而请求的对象就是接收端的NetServer(后边会讲)，客户端配置已经在EventBusOptions中事先配置好了。我们来看看connect方法是如何建立连接的：

~~~java
synchronized void connect() {
  if (connected) {
    throw new IllegalStateException("Already connected");
  }
  client.connect(serverID.port, serverID.host, res -> {
    if (res.succeeded()) {
      connected(res.result());
    } else {
      close();
    }
  });
}
~~~

可以看到这里很简单地调用了NetClient#connect方法建立TCP连接，如果建立连接成功的话会得到一个NetSocket对象。Event Bus接着将其传至connected方法中进行处理：

~~~java
private synchronized void connected(NetSocket socket) {
  this.socket = socket;
  connected = true;
  socket.exceptionHandler(t -> close());
  socket.closeHandler(v -> close());
  socket.handler(data -> {
    // Got a pong back
    vertx.cancelTimer(timeoutID);
    schedulePing();
  });
  // Start a pinger
  schedulePing();
  for (ClusteredMessage message : pending) {
    Buffer data = message.encodeToWire();
    metrics.messageWritten(message.address(), data.length());
    socket.write(data);
  }
  pending.clear();
}
~~~

首先Event Bus通过exceptionHandler和closeHandler方法给连接对应的NetSocket绑定异常回调和连接关闭回调，触发的时候都调用close方法关闭连接；为了保证不丢失连接，消息发送方每隔一段时间就需要对消息接收方发送一次心跳包（PING），如果消息接收方在一定时间内没有回复，那么就认为连接丢失，调用close方法关闭连接。心跳检测的逻辑在schedulePing方法中，比较清晰，这里就不详细说了。大家会发现ConnectionHolder里也有个消息队列（缓冲区）pending，并且这里会将队列中的消息依次通过TCP发送至接收端。为什么需要这样呢？其实，这要从创建TCP客户端说起。创建TCP客户端这个过程应该是异步的，需要消耗一定时间，而ConnectionHolder中封装的connect方法却是同步式的。前面我们刚刚看过，通过connect方法建立连接以后会接着调用writeMessage方法发送消息，而这时候客户端连接可能还没建立，因此需要这么个缓冲区先存着，等着连接建立了再一块发送出去.

至于发送消息的writeMessage方法，其逻辑一目了然：

~~~java
synchronized void writeMessage(ClusteredMessage message) {
  if (connected) {
    Buffer data = message.encodeToWire();
    metrics.messageWritten(message.address(), data.length());
    socket.write(data);
  } else {
    if (pending == null) {
      pending = new ArrayDeque<>();
    }
    pending.add(message);
  }
}
~~~

如果连接已建立，Event Bus就会调用对应ClusteredMessage的encodeToWire方法将其转化为字节流Buffer，然后记录metrics信息，最后通过socket的write方法将消息写入到Socket中，这样消息就从发送端通过TCP发送到了接收端。如果连接未建立，就如之前讲的那样，先把消息存到消息队列中，等连接建立了再一块发出去。

这样，Clustered Event Bus下消息的发送逻辑就理清楚了。下面我们看一下接收端是如何接收消息并在本地进行消息的处理的。

### 消息的接收 ###

一开始我们提到过，每个节点的Clustered Event Bus在启动时都会创建一个NetServer作为接收消息的TCP服务端。TCP Server的port和host可以在EventBusOptions中指定，如果不指定的话默认随机分配port，然后Event Bus会根据NetServer的配置来生成当前节点的ServerID。

创建TCP Server的逻辑在start方法中，与接受消息有关的逻辑就是这一句：


> server.connectHandler(getServerHandler());

我们知道，NetServer的connectHandler方法用于绑定对服务端Socket的处理函数，而这里绑定的处理函数是由getServerHandler方法生成的：

~~~java
private Handler<NetSocket> getServerHandler() {
  return socket -> {
    RecordParser parser = RecordParser.newFixed(4, null);
    Handler<Buffer> handler = new Handler<Buffer>() {
      int size = -1;
      public void handle(Buffer buff) {
        if (size == -1) {
          size = buff.getInt(0);
          parser.fixedSizeMode(size);
        } else {
          ClusteredMessage received = new ClusteredMessage();
          received.readFromWire(buff, codecManager);
          metrics.messageRead(received.address(), buff.length());
          parser.fixedSizeMode(4);
          size = -1;
          if (received.codec() == CodecManager.PING_MESSAGE_CODEC) {
            // Just send back pong directly on connection
            socket.write(PONG);
          } else {
            deliverMessageLocally(received);
          }
        }
      }
    };
    parser.setOutput(handler);
    socket.handler(parser);
  };
}
~~~

逻辑非常清晰。这里Event Bus使用了RecordParser来获取发送过来的对应长度的Buffer，并将其绑定在NetServer的Socket上。真正的解析Buffer并处理的逻辑在内部的handler中。之前ClusteredMessage中的Wire Protocol规定Buffer的首部第一个int值为要发送Buffer的长度（逻辑见ClusteredMessage#encodeToWire方法），因此这里首先获取长度，然后给parser设定正确的fixed size，这样parser就可以截取正确长度的Buffer流了。下面Event Bus会创建一个空的ClusteredMessage，然后调用其readFromWire方法从Buffer中重建消息。当然这里还要记录消息已经读取的metrics信息。接着检测收到的消息实体类型是否为心跳检测包(PING)，如果是的话就发送回ACK消息(PONG)；如果不是心跳包，则代表是正常的消息，Event Bus就调用我们熟悉的deliverMessageLocally函数在本地进行分发处理，接下来的过程就和Local模式一样了。

~~~java
protected <T> boolean deliverMessageLocally(MessageImpl msg) {
    msg.setBus(this);
    Handlers handlers = handlerMap.get(msg.address());
    if (handlers != null) {
      if (msg.send()) {
        //Choose one
        HandlerHolder holder = handlers.choose();
        metrics.messageReceived(msg.address(), !msg.send(), isMessageLocal(msg), holder != null ? 1 : 0);
        if (holder != null) {
          deliverToHandler(msg, holder);
        }
      } else {
        // Publish
        metrics.messageReceived(msg.address(), !msg.send(), isMessageLocal(msg), handlers.list.size());
        for (HandlerHolder holder: handlers.list) {
          deliverToHandler(msg, holder);
        }
      }
      return true;
    } else {
      metrics.messageReceived(msg.address(), !msg.send(), isMessageLocal(msg), 0);
      return false;
    }
  }
~~~ 


## 线程模型 ##

### Event Loop线程 ###
首先回顾一下Event Loop线程，它会不断地轮询获取事件，并将获取到的事件分发到对应的事件处理器中进行处理：

Vert.x Event Loop

Vert.x线程模型中最重要的一点就是：永远不要阻塞Event Loop线程。因为一旦处理事件的线程被阻塞了，事件就会一直积压着不能被处理，整个应用也就不能正常工作了。

Vert.x中内置一种用于检测Event Loop是否阻塞的线程：vertx-blocked-thread-checker。一旦Event Loop处理某个事件的时间超过一定阈值（默认为2000ms）就会警告，如果阻塞的时间过长就会抛出异常。Block Checker的实现原理比较简单，底层借助了JUC的TimerTask，定时计算每个Event Loop线程的处理事件消耗的时间，如果超时就进行相应的警告。

### Vert.x Thread ###

Vert.x中的Event Loop线程及Worker线程都用VertxThread类表示，并通过VertxThreadFactory线程工厂来创建。其实就是在普通线程的基础上存储了额外的数据（如对应的Vert.x Context，最大执行时长，当前执行时间，是否为Worker线程等）,VertxThreadFactory创建Vert.x线程的过程也非常简单：

~~~ java
@Override
public Thread newThread(Runnable runnable) {
  VertxThread t = new VertxThread(runnable, prefix + threadCount.getAndIncrement(), worker, maxExecTime);

  if (checker != null) {
    checker.registerThread(t);
  }
  addToMap(t);

  t.setDaemon(false);
  return t;
}
~~~ 

除了创建VertxThread线程之外，VertxThreadFactory还会将此线程注册至Block Checker线程中以监视线程的阻塞情况，并且将此线程添加至内部的weakMap中。这个weakMap作用只有一个，就是在注销对应的Verticle的时候可以将每个VertxThread中的Context实例清除(unset)。为了保证资源不被一直占用，这里使用了WeakHashMap来存储每一个VertxThread。当里面的VertxThread的引用不被其他实例持有的时候，它就会被标记为可清除的对象，等待GC。

~~~ java
BlockedThreadChecker(long interval, long warningExceptionTime) {
    timer = new Timer("vertx-blocked-thread-checker", true);
    timer.schedule(new TimerTask() {
      @Override
      public void run() {
        synchronized (BlockedThreadChecker.this) {
          long now = System.nanoTime();
          for (VertxThread thread : threads.keySet()) {
            long execStart = thread.startTime();
            long dur = now - execStart;
            final long timeLimit = thread.getMaxExecTime();
            if (execStart != 0 && dur > timeLimit) {
              final String message = "Thread " + thread + " has been blocked for " + (dur / 1000000) + " ms, time limit is " + (timeLimit / 1000000);
              if (dur <= warningExceptionTime) {
                log.warn(message);
              } else {
                VertxException stackTrace = new VertxException("Thread blocked");
                stackTrace.setStackTrace(thread.getStackTrace());
                log.warn(message, stackTrace);
              }
            }
          }
        }
      }
    }, interval, interval);
  }
~~~ 


### Vert.x Context ###

Vert.x底层中一个重要的概念就是Context，每个Context都会绑定着一个Event Loop线程（而一个Event Loop线程可以对应多个Context）。我们可以把Context看作是控制一系列的Handler的执行作用域及顺序的上下文对象。

每当Vert.x底层将事件分发至Handler的时候，Vert.x都会给此Handler钦点一个Context用于处理任务：

如果当前线程是Vert.x线程(VertxThread)，那么Vert.x就会复用此线程上绑定的Context；如果没有对应的Context就创建新的
如果当前线程是普通线程，就创建新的Context
Vert.x中存在三种Context，与之前的线程种类相对应：

- EventLoopContext
- WorkerContext
- MultiThreadedWorkerContext

Event loop context
每个Event Loop Context都会对应着唯一的一个EventLoop，即一个Event Loop Context只会在同一个Event Loop线程上执行任务。在创建Context的时候，Vert.x会自动根据轮询策略选择对应的EventLoop:

~~~ java
protected ContextImpl(VertxInternal vertx, WorkerPool internalBlockingPool, WorkerPool workerPool, String deploymentID, JsonObject config,
                        ClassLoader tccl) {
    // ...
    EventLoopGroup group = vertx.getEventLoopGroup();
    if (group != null) {
      this.eventLoop = group.next();
    } else {
      this.eventLoop = null;
    }
    // ...
  }
~~~ 

在Netty中，EventLoopGroup代表一组EventLoop，而从中获取EventLoop的方法则是next方法。EventLoopGroup中EventLoop的数量由CPU内核数目所确定。Vert.x这里使用了Netty NIO对应的NioEventLoop：

~~~ java
eventLoopGroup = new NioEventLoopGroup(options.getEventLoopPoolSize(), eventLoopThreadFactory);
eventLoopGroup.setIoRatio(NETTY_IO_RATIO);
~~~ 


Event Loop Context会在对应的EventLoop中执行Handler进行事件的处理（IO事件，非阻塞）。Vert.x会保证同一个Handler会一直在同一个Event Loop线程中执行，这样可以简化线程模型，让开发者在写Handler的时候不需要考虑并发的问题，非常方便。

我们来粗略地看一下Handler是如何在EventLoop上执行的。EventLoopContext中实现了executeAsync方法用于包装Handler中事件处理的逻辑并将其提交至对应的EventLoop中进行执行：

~~~ java
public void executeAsync(Handler<Void> task) {
  // No metrics, we are on the event loop.
  nettyEventLoop().execute(wrapTask(null, task, true, null));
}
~~~ 

这里Vert.x使用了wrapTask方法将Handler封装成了一个Runnable用于向EventLoop中提交。代码比较直观，大致就是检查当前线程是否为Vert.x线程，然后记录事件处理开始的时间，给当前的Vert.x线程设置Context，并且调用Handler里面的事件处理方法。具体请参考源码，这里就不贴出来了。

那么把封装好的task提交到EventLoop以后，EventLoop是怎么处理的呢？这就需要更多的Netty相关的知识了。根据Netty的模型，Event Loop线程需要处理IO事件，普通事件（即我们的Handler）以及定时事件（比如Vert.x的setTimer）。Vert.x会提供一个NETTY_IO_RATIO给Netty代表EventLoop处理IO事件时间占用的百分比（默认为50，即IO事件时间占用:非IO事件时间占用=1:1）。回顾一下netty的EventLoop源码,启动的时候，它会不断轮询IO时间及其它事件并进行处理：

~~~ java
@Override
protected void run() {
    for (;;) {
        try {
            switch (selectStrategy.calculateStrategy(selectNowSupplier, hasTasks())) {
                case SelectStrategy.CONTINUE:
                    continue;
                case SelectStrategy.SELECT:
                    select(wakenUp.getAndSet(false));

                    if (wakenUp.get()) {
                        selector.wakeup();
                    }
                default:
                    // fallthrough
            }

            cancelledKeys = 0;
            needsToSelectAgain = false;
            final int ioRatio = this.ioRatio;
            if (ioRatio == 100) {
                processSelectedKeys();
                runAllTasks();
            } else {
                final long ioStartTime = System.nanoTime();

                processSelectedKeys();

                final long ioTime = System.nanoTime() - ioStartTime;
                runAllTasks(ioTime * (100 - ioRatio) / ioRatio);
            }

            if (isShuttingDown()) {
                closeAll();
                if (confirmShutdown()) {
                    break;
                }
            }
        } catch (Throwable t) {
            // process the error
            // ...
        }
    }
}
~~~ 

这里面Netty会调用processSelectedKeys方法进行IO事件的处理，并且会计算出处理IO时间所用的事件然后计算出给非IO事件处理分配的时间，然后调用runAllTasks方法执行所有的非IO任务（这里面就有我们的各个Handler）。

runAllTasks会按顺序从内部的任务队列中取出任务(Runnable)然后进行安全执行。而我们刚才调用的executeAsync方法其实就是将包装好的Handler置入NioEventLoop内部的任务队列中等待执行。

### Worker context ###
顾名思义，Worker Context用于跑阻塞任务。与Event Loop Context相似，每一个Handler都只会跑在固定的Worker线程下。

