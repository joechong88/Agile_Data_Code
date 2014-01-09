/* Set Home Directory - where we install software */
%default HOME `echo /usr/local`

/* MongoDB libraries and configuration */
REGISTER $HOME/mongo-hadoop/mongo-java-driver-2.11.3.jar
REGISTER $HOME/mongo-hadoop/core/target/mongo-hadoop-core-1.2.0.jar
REGISTER $HOME/mongo-hadoop/pig/target/mongo-hadoop-pig-1.2.0.jar

DEFINE MongoStorage com.mongodb.hadoop.pig.MongoStorage();

per_document_scores = LOAD '/tmp/topics_per_document.txt' AS (message_id:chararray, topics:bag{topic:tuple(word:chararray, score:double)});
store per_document_scores into 'mongodb://localhost/agile_data.topics_per_email' using MongoStorage();
