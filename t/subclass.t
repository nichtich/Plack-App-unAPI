use strict;
use warnings;
use v5.10;
use Test::More;
use Plack::Test;
use HTTP::Request::Common;

{
    package unAPIServerTest;

    use parent 'Plack::App::unAPI';

    sub formats {
        return {
            txt  => [ 'text/plain', docs => 'http://example.com' ],
            json => [ 'application/json' ], 
        }
    }

    sub format_json {
        return $_[1] eq 'bar' ? '{"x":1}' : undef; 
    }

    sub format_txt {
        return $_[1] eq 'foo' ? "FOO" : undef;
    }
}


my $app = unAPIServerTest->new;

test_psgi $app, sub {
    my $cb = shift;

    my $res = $cb->(GET '/');
    is $res->code, 300, "Multiple Choices";
    is_deeply
        [sort grep { /^<format / } split "\n", $res->content],
        ['<format name="json" type="application/json" />', 
         '<format name="txt" type="text/plain" docs="http://example.com" />'],
        'list formats';

    $res = $cb->(GET '/?id=foo&format=txt');
    is $res->code, 200, "Ok";
    is $res->content, "FOO", "FOO";
 
    $res = $cb->(GET '/?id=foo&format=json');
    is $res->code, 404, "Not Found";

    $res = $cb->(GET '/?id=bar&format=json');
    is $res->code, 200, "Ok";
    is $res->content, '{"x":1}', "format=json";
};

done_testing;
