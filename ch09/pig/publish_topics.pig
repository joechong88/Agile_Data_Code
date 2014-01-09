/* Set Home Directory - where we install software */
%default HOME `echo /usr/local`

/* Avro uses json-simple, and is in piggybank until Pig 0.12, where AvroStorage and TrevniStorage are builtins */
REGISTER $HOME/pig/build/ivy/lib/Pig/avro-1.7.4.jar
REGISTER $HOME/pig/build/ivy/lib/Pig/json-simple-1.1.jar
REGISTER $HOME/pig/contrib/piggybank/java/piggybank.jar

DEFINE MongoStorage com.mongodb.hadoop.pig.MongoStorage();

token_reply_rates = LOAD '/tmp/reply_rates.txt' AS (token:chararray, reply_rate:double);
store token_reply_rates into 'mongodb://localhost/agile_data.token_reply_rates' using MongoStorage();

token_no_reply_rates = LOAD '/tmp/no_reply_rates.txt' AS (token:chararray, reply_rate:double);
store token_no_reply_rates into 'mongodb://localhost/agile_data.token_no_reply_rates' using MongoStorage();

p_token = LOAD '/tmp/p_token.txt' AS (token:chararray, prob:double);
store p_token into 'mongodb://localhost/agile_data.p_token' using MongoStorage();
