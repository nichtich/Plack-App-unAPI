use strict;
use warnings;
use Test::More;
use Plack::Test;
use HTTP::Request::Common;
use Plack::App::unAPI;
use Plack::Request;

my $app1 = sub { [ 404, [ 'Content-Type' => 'application/xml' ], [ '<xml/>' ] ] };

{
    package MyApp;
    use parent 'Plack::Component';

    sub call {
        my $req = Plack::Request->new($_[1]);
        my $id = $req->param('id');
        return [ $id ? 200 : 404, 
            [ 'Content-Type' => 'text/plain' ], [ "ID: $id" ] ];
    }
};

my $app2 = MyApp->new;

my @xml = ( 
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<format name="xml" type="application/xml" />',
    '<format name="txt" type="text/plain" docs="http://example.com" />',
    '</formats>' );

my $app = unAPI(
    xml  => [ $app1 => 'application/xml' ],
    txt  => [ $app2 => 'text/plain', docs => 'http://example.com' ]
);

test_psgi $app, sub {
    my ($cb, $res) = @_;

    foreach ('/','/?format=xml') {
        $res = $cb->(GET $_);
        is( $res->code, 300, "Multiple Choices for $_" );
        is_deeply(
            [sort (split "\n", $res->content)],
            [sort ('<formats>',@xml)], 'list formats without id'
        );
    }

    $res = $cb->(GET "/?id=abc");
    is( $res->code, 300, 'Multiple Choices' );
    is_deeply(
        [sort (split "\n", $res->content)],
        [sort ('<formats id="abc">',@xml)], 'list formats with id'
    );

    $res = $cb->(GET "/?id=0&format=xml");
    is( $res->code, 404, 'Not found (via format=xml)' );
    is( $res->content, "<xml/>", "format=xml" );

    $res = $cb->(GET "/?id=abc&format=txt");
    is( $res->code, 200, 'Found (via format=txt)' );
    is( $res->content, "ID: abc", "format=txt" );

};

done_testing;
