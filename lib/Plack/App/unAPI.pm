use strict;
use warnings;
package Plack::App::unAPI;
#ABSTRACT: Serve via unAPI

use 5.010;
use parent qw(Plack::Component Exporter);
use Plack::Request;

our @EXPORT = qw(unAPI);

## no critic
sub unAPI(@) { __PACKAGE__->new(@_) }
## use critic

sub new {
    my $proto = shift;
    my $class = ref $proto || $proto;

    my $self = bless {@_}, $class;

    foreach (keys %$self) {
        my ($app, $type, %about) = @{$self->{$_}};
        $self->{$_} = { app => $app, type => $type, %about };
    }

    $self;
}

sub call {
    my ($self, $env) = @_;
    my $req    = Plack::Request->new($env);
    my $format = $req->param('format') // '';
    my $id     = $req->param('id') // '';

    # here we could first lookup the resource at the server
    # and sent 404 if no known format was specified

    if ($format eq '' or $id eq '') {
        return $self->formats($id);
    }

    my $app = $self->{$format}->{app};

    if (!$app) {
        my $res = $self->formats($id);
        $res->[0] = 406; # Not Acceptable
        return $res;
    }

    my $res = eval { $app->( $env ); };
    my $error = $@;

    if ( $error ) {
        $error = "Internal crash with format=$format and id=$id: $@";
    } elsif (!(
        # check whether PSGI conforms to PSGI specification
        ref($res) and ref($res) eq 'ARRAY' and 
        (@$res == 3 or @$res == 2) and
        $res->[0] =~ /^\d+$/ and $res->[0] >= 100 and
        ref $res->[1] and $res->[1] eq 'ARRAY'
    )) {
        $error = "No PSGI response for format=$format and id=$id";
    }
    # we may also check response type...

    return [ 500, [ 'Content-Type' => 'text/plain' ], [ $error ] ] if $error;
 
    $res;
}

sub formats {
    my ($self, $id) = @_;

    my $status = 300; # Multiple Choices
    my $type   = 'application/xml; charset: utf-8';
    my @xml    = $id eq '' ?  '<formats>' 
               : "<formats id=\"" . _xmlescape($id) . "\">";

    while (my ($name, $format) = each %$self) {
        my $line = "<format name=\"$name\" type=\"".$format->{type}."\"";
        if ( $format->{docs} ) {
            push @xml, "$line docs=\"" . _xmlescape($format->{docs}) . '" />';
        } else {
            push @xml, "$line />"
        }
    }

    return [ $status, [ 'Content-Type' => $type ],
        [ join "\n", '<?xml version="1.0" encoding="UTF-8"?>', @xml, '</formats>' ] ];
}

sub _xmlescape {
    my $xml = shift;
    if ($xml =~ /[\&\<\>"]/) {
        $xml =~ s/\&/\&amp\;/g;
        $xml =~ s/\</\&lt\;/g;
        $xml =~ s/\>/\&gt\;/g;
        $xml =~ s/"/\&quot\;/g;
    }
    return $xml;
}

1;

=head1 DESCRIPTION

This implements an unAPI server as PSGI application. unAPI is a tiny HTTP API
to query discretely identified objects in different formats. See
L<http://unapi.info> for details. The basic idea is to have two HTTP GET query
parameters: B<id> to select an object, and B<format> to select a format. If no
(or no supported) format is specified, a list of formats (in XML) is returned
instead. This implementation routes the request to different PSGI applications
based on a known format parameter, or sends the format list.

=head1 SYNOPSIS

    use Plack::App::unAPI;

    my $app1 = sub { ... };
    my $app2 = sub { ... };
    my $app3 = sub { ... };

    unAPI
        json => [ $app1 => 'application/javascript' ],
        xml  => [ $app2 => 'application/xml' ],
        txt  => [ $app3 => 'text/plain', docs => 'http://example.com' ];

To run this script you can simply call C<plackup yourscript.psgi>. Then try:

    http://localhost:5000/?id=abc&format=json  # calls $app1
    http://localhost:5000/?id=abc&format=xml   # calls $app2
    http://localhost:5000/?id=abc&format=txt   # calls $app3
    http://localhost:5000/                     # returns list of formats
    http://localhost:5000/?format=xml          # returns list of formats
    http://localhost:5000/?id=abc              # returns list of formats

=method new ( %formats )

To create a server object you must provide a list of mappings between format
names and PSGI applications to serve requests for the particular format. Each
application is wrapped in an array reference, followed by its MIME type and
optional information fields about the format. So the general form is: 

    format => [ $app => $type, %about ]

The following information fields are supported:

=over

=item docs

An URL of a document that describes the format

=back 

By default, the result is checked to be valid PSGI (at least to some degree)
and errors in single applications are catched - in this case a response with
HTTP status code 500 is returned.

=method unAPI ( %formats )

The C<unAPI> keyword as constructor alias is exported by default. To prevent
exporting, include this module via C<use Plack::App::unAPI ();>.

=method formats ( [$id] )

Returns a PSGI response with status 300 (Multiple Choices) and an XML document
that lists all formats.

=head1 SEE ALSO

Chudnov et al. (2006): I<Introducing unAP>. In: Ariadne, 48,
<http://www.ariadne.ac.uk/issue48/chudnov-et-al/>.

=cut
