use Test::More tests => 16;
use strict;
use warnings;

use Sys::Hostname;
my $unique = hostname . "-$^O-$^V"; #hostname-os-perlversion
my $exchange = "ski_test_x-$unique";
my $queuename = "ski_test_q-$unique";
my $exchange_404 = "ski_nonexistent.$unique." . int( rand( 65535 ) );
my $routekey = '';

my $dtag=(unpack("L",pack("N",1)) != 1)?'0100000000000000':'0000000000000001';
my $host = $ENV{'MQHOST'} || "dev.rabbitmq.com";

my $READER_CHANNEL = 1;
my $WRITER_CHANNEL = 2;

use_ok('Net::AMQP::RabbitMQ');

# this test detects the bug wherein the following sequence of events leads to unexpected behavior:
# 1) publish to a non-existent exchange on some channel
# 2) get from an existing queue w/ a ready message on some other channel
# error will be: "Unexpected header 1"

# first, with a separate MQ object, create a queue with one message in it.
# this must be done in a separate thread of execution so we do
# not affect the state in the parent process, which has to do
# a very precise sequence of calls to trigger the bug. another way to
# trigger the bug would be to create and populate this queue manually
# before running the tests on $mq2
my $mq1 = Net::AMQP::RabbitMQ->new();
ok($mq1);

eval { $mq1->connect($host, { user => "guest", password => "guest" }); };
is($@, '', "connect");

eval { $mq1->channel_open( 1 ); };
is($@, '', "reader channel_open");

eval { $queuename = $mq1->queue_declare(1, $queuename, { passive => 0, durable => 0, exclusive => 0, auto_delete => 0 }); };
is($@, '', "queue_declare");
isnt($queuename, '', "queue_declare -> private name");

$mq1->exchange_declare( 1, $exchange, {} );
is($@, '', "exchange_declare");

eval { $mq1->queue_bind(1, $queuename, $exchange, $routekey); };
is($@, '', "queue_bind");

eval { $mq1->publish( 1, '', "foobar", { exchange => $exchange }); };
is($@, '', "publish to existing, bound exchange");

# now, with a second MQ object, create a queue with one message in it.
# this must be done in a separate thread of execution so we do
# not affect the state in the parent process, which has to do
# a very precise sequence of calls to trigger the bug
my $mq2 = Net::AMQP::RabbitMQ->new();
ok($mq2);

eval { $mq2->connect($host, { user => "guest", password => "guest" }); };
is($@, '', "connect");

eval { $mq2->channel_open( $READER_CHANNEL ); };
is($@, '', "reader channel_open");

eval { $mq2->channel_open( $WRITER_CHANNEL ); };
is($@, '', "writer channel_open");

# try to put something in an exchange that does not exist. this will succeed, but
# cause bad state to exist in the driver
eval { $mq2->publish( $WRITER_CHANNEL, '', "foobar", { exchange => $exchange_404 }); };
is($@, '', "publish (non-existing exchange)");

my $getr;
eval { $getr = $mq2->get( $READER_CHANNEL, $queuename); };
is($@, '', "get");
is($getr, undef, "get should return empty");

