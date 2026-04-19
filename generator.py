#!/usr/bin/env python3
"""Generate lesson pages from metadata"""

LESSONS = {
    "001": {
        "title": "Event-Driven Architecture: Request/Reply Processing",
        "date": "Jan 22, 2018",
        "summary": "How to do request/reply within async messaging using correlation IDs.",
        "articles": [
            ("Correlation IDs","https://www.enterpriseintegrationpatterns.com/CorrelationIdentifier.html"),
            ("Request-Reply","https://www.enterpriseintegrationpatterns.com/RequestReply.html"),
        ],
        "deep_dives": [
            ("Kafka Request Reply","https://kafka.apache.org/documentation/#georedundancy"),
            ("Messaging Patterns","../scalability.html#messaging"),
        ],
    },
    "002": {
        "title": "How Kafka Differs From Standard Messaging", 
        "date": "Jan 29, 2018",
        "summary": "Kafka's log-based architecture vs traditional message queues.",
        "articles": [
            ("Kafka Architecture","https://kafka.apache.org/intro"),
            ("Log Structured Merge","https://www.confluent.io/blog/log-structured-merge-lsm-style-storage/"),
        ],
        "deep_dives": [
            ("Kafka Deep Dive","../kafka/01-kafka-architecture-deep-dive.html"),
            ("Kafka vs RabbitMQ","https://www.confluent.io/blog/kafka-vs-rabbitmq-amqp-streams-messaging/"),
        ],
    },
    "003": {
        "title": "Gaining Technical Breadth",
        "date": "Feb 5, 2018",
        "summary": "The 20-minute rule for learning outside your expertise.",
        "articles": [
            ("T-Shaped Skills","https://medium.com/re-writing-developer-talent/9f12fe1c22c9"),
            ("Learning How to Learn","https://www.coursera.org/learn/learning-how-to-learn"),
        ],
        "deep_dives": [
            ("ThoughtWorks Radar","https://www.thoughtworks.com/radar"),
            ("InfoQ Architecture","https://www.infoq.com/architecture-design/"),
        ],
    },
    "111": {
        "title": "CAP Theorem Illustrated",
        "date": "Apr 12, 2021",
        "summary": "Consistency vs Availability tradeoffs in distributed systems.",
        "articles": [
            ("Understanding CAP","https://www.infoq.com/articles/understanding-cap/"),
            ("CAP Theorem","https://martinfowler.com/bliki/CAPTheorem.html"),
        ],
        "deep_dives": [
            ("CAP Twelve Years Later","https://people.eecs.berkeley.edu/~brewer/cs262b-2004.pdf"),
            ("CAP and Databases","../performance.html#databases"),
        ],
    },
    "162": {
        "title": "Microservices Architecture",
        "date": "Jun 5, 2023",
        "summary": "Core characteristics: independent deployability, own database.",
        "articles": [
            ("Microservices Guide","https://martinfowler.com/microservices/"),
            ("When to Use Microservices","https://shopify.engineering/microservices-when-not-to-use/"),
        ],
        "deep_dives": [
            ("Building Microservices","../scalability.html#microservices"),
            ("Microservices Patterns","../architecture.html"),
        ],
    },
}

# Generate pages
import os
for num, data in LESSONS.items():
    filename = f"lessons/lesson{num}.html"
    print(f"Would create: {filename}")
    # In full implementation, generate HTML here

print(f"\n{LESSONS} lessons defined")
print("Run generator.py to create all pages")