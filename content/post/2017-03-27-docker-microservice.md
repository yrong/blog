---
author: Ron
catalog: true
date: 2017-03-27T00:00:00Z
tags:
- docker
- microservice
title: Build a NodeJS microservice and deploy it to Docker
---

Build a NodeJS microservice and deploy it to Docker
<!--more-->

# Build a NodeJS microservice and deploy it to Docker

### Stack
We’ll use a simple NodeJS service with a MongoDB for our backend.

- NodeJS 7.5.0
- MongoDB 3.4.2
- Docker for Mac 1.13.0

### Architecture

![Microservice Architecture](/blog/img/micro-service/1-XdnoQCqmM_faIljmW5nxFA.png)

### Microservices

- [Movies Service example](https://github.com/yrong/cinema-microservice/blob/master/movies-service)
- [Cinema Catalog Service example](https://github.com/yrong/cinema-microservice/blob/master/cinema-catalog-service)
- [Booking Service example](https://github.com/yrong/cinema-microservice/blob/master/booking-service)
- [Payment Service example](https://github.com/yrong/cinema-microservice/blob/master/payment-service)
- [Notification Service example](https://github.com/yrong/cinema-microservice/blob/master/notification-service)
- [API Gateway Service example](https://github.com/yrong/cinema-microservice/blob/master/api-gateway)

### Api Gateway

> An API Gateway is a server that is the single entry point into the system. It is similar to the Facade pattern from object oriented design.

The API Gateway encapsulates the internal system architecture and provides an API that is tailored to each client. It might have other responsibilities such as authentication, monitoring, load balancing, caching, request shaping and management, and static response handling.

![Microservice Api Gateway](/blog/img/micro-service/1-Mjx_b0EII3RrPvn3Bw6K1w.png)


### Blog posts

- [Build a NodeJS cinema microservice and deploying it with docker (part 1)](https://medium.com/@cramirez92/build-a-nodejs-cinema-microservice-and-deploying-it-with-docker-part-1-7e28e25bfa8b)
- [Build a NodeJS cinema microservice and deploying it with docker (part 2)](https://medium.com/@cramirez92/build-a-nodejs-cinema-microservice-and-deploying-it-with-docker-part-2-e05cc7b126e0)
- [Build a NodeJS cinema booking microservice and deploying it with docker (part 3)](https://medium.com/@cramirez92/build-a-nodejs-cinema-booking-microservice-and-deploying-it-with-docker-part-3-9c384e21fbe0)
- [Build a NodeJS cinema microservice and deploying it with docker (part 4)](https://medium.com/@cramirez92/build-a-nodejs-cinema-api-gateway-and-deploying-it-to-docker-part-4-703c2b0dd269#.en6g5buwl)
- [Deploy a Nodejs microservices to a Docker Swarm Cluster (Docker from zero to hero)](https://medium.com/@cramirez92/deploy-a-nodejs-microservices-to-a-docker-swarm-cluster-docker-from-zero-to-hero-464fa1369ea0#.548ni3uxv)
