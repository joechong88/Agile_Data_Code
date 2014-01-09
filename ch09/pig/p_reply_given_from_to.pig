/* Set Home Directory - where we install software */
%default HOME `echo /usr/local`

/* Avro uses json-simple, and is in piggybank until Pig 0.12, where AvroStorage and TrevniStorage are builtins */
REGISTER $HOME/pig/build/ivy/lib/Pig/avro-1.7.4.jar
REGISTER $HOME/pig/build/ivy/lib/Pig/json-simple-1.1.jar
REGISTER $HOME/pig/contrib/piggybank/java/piggybank.jar

DEFINE AvroStorage org.apache.pig.piggybank.storage.avro.AvroStorage();

/* MongoDB libraries and configuration */
REGISTER $HOME/mongo-hadoop/mongo-java-driver-2.11.3.jar
REGISTER $HOME/mongo-hadoop/core/target/mongo-hadoop-core-1.2.0.jar
REGISTER $HOME/mongo-hadoop/pig/target/mongo-hadoop-pig-1.2.0.jar

DEFINE MongoStorage com.mongodb.hadoop.pig.MongoStorage();

set default_parallel 20
set mapred.map.tasks.speculative.execution false
set mapred.reduce.tasks.speculative.execution false

rmf /tmp/sent_counts.txt
rmf /tmp/replies.txt
rmf /tmp/direct_replies.txt
rmf /tmp/reply_counts.txt
rmf /tmp/reply_ratios.txt
rmf /tmp/overall_replies.txt
rmf /tmp/smooth_distributions.avro
rmf /tmp/sent_count_overall_replies.txt
rmf /tmp/p_sent_from_to.txt
rmf /tmp/no_reply_ratios.txt

-- Count both from addresses and reply_to addresses as 
emails = load '/tmp/gmail_data' using AvroStorage();
clean_emails = filter emails by (from.address is not null) and (reply_tos is null);
sent_emails = foreach clean_emails generate from.address as from, 
                                            flatten(tos.address) as to, message_id;

/* Calculate sent counts */
sent_counts = foreach (group sent_emails by (from, to)) generate flatten(group) as (from, to), 
                                                                 COUNT_STAR(sent_emails) as total;

/* Project all from/to pairs for non-mailing list emails to get replies */
replies = filter emails by (from is not null) and (reply_tos is null) and (in_reply_to is not null);
replies = foreach replies generate from.address as from,
                                   flatten(tos.address) as to,
                                   in_reply_to;
replies = filter replies by in_reply_to != 'None';

/* Now join a copy of the emails by message id to the in_reply_to of our emails */
with_reply = join sent_emails by message_id left outer, replies by in_reply_to;

split with_reply into has_reply if (in_reply_to is not null), no_reply if (in_reply_to is null);

store has_reply into '/tmp/has_reply.txt';
store no_reply into '/tmp/no_reply.txt';

/* Filter out mailing lists - only direct replies where from/to match up */
direct_replies = filter has_reply by (sent_emails::from == replies::to) and (sent_emails::to == replies::from);

/* Count replies */
trimmed_replies = foreach direct_replies generate sent_emails::from as from, sent_emails::to as to;
reply_counts = foreach (group trimmed_replies by (from, to)) generate flatten(group) as (from, to), 
                                                                      COUNT_STAR(trimmed_replies) as total;
-- Join to get replies with sent mails
sent_replies = join sent_counts by (from, to), reply_counts by (from, to);

-- Calculate from/to reply ratios for each pair of from/to
reply_ratios = foreach sent_replies generate sent_counts::from as from, 
                                             sent_counts::to as to, 
                                             (double)reply_counts::total/sent_counts::total as ratio:double;
reply_ratios = foreach reply_ratios generate from, to, (ratio > 1.0 ? 1.0 : ratio) as ratio; -- Error cleaning
store reply_ratios into '/tmp/reply_ratios.txt';
store reply_ratios into 'mongodb://localhost/agile_data.from_to_reply_ratios' using MongoStorage();

trimmed_no_replies = foreach no_reply generate sent_emails::from as from, sent_emails::to as to;
no_reply_counts = foreach (group trimmed_no_replies by (from, to)) generate flatten(group) as (from, to),
                                                       COUNT_STAR(trimmed_no_replies) as total;
sent_no_replies = join sent_counts by (from, to), no_reply_counts by (from, to);
no_reply_ratios = foreach sent_no_replies generate sent_counts::from as from,
                                                   sent_counts::to as to,
                                                   (double)no_reply_counts::total/sent_counts::total as ratio:double;
no_reply_ratios = foreach no_reply_ratios generate from, to, (ratio > 1.0 ? 1.0 : ratio) as ratio;
store no_reply_ratios into '/tmp/no_reply_ratios.txt';
store no_reply_ratios into 'mongodb://localhost/agile_data.from_to_no_reply_ratios' using MongoStorage();

-- Calculate the overall reply ratio - period.
overall_replies = foreach (group sent_replies all) generate 'overall' as key:chararray, 
                                                            SUM(sent_replies.sent_counts::total) as sent,
                                                            SUM(sent_replies.reply_counts::total) as replies,
                                                            (double)SUM(sent_replies.reply_counts::total)/(double)SUM(sent_replies.sent_counts::total) as reply_ratio; 
overall_replies = LIMIT overall_replies 1;
store overall_replies into '/tmp/overall_replies.txt';
store overall_replies into 'mongodb://localhost/agile_data.overall_reply_ratio' using MongoStorage();

all_emails = foreach (group sent_counts all) generate SUM(sent_counts.total) as total;
p_sent_from_to = foreach (group sent_counts by (from, to)) generate FLATTEN(group) as (from, to), 
                                                                    (double)SUM(sent_counts.total)/(double)all_emails.total;
store p_sent_from_to into '/tmp/p_sent_from_to.txt';
store p_sent_from_to into 'mongodb://localhost/agile_data.p_sent_from_to' using MongoStorage();
