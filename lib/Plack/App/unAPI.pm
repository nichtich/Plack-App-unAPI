use strict;
use warnings;
package Plack::App::unAPI;
#ABSTRACT: Serve via unAPI
use v5.10.1;

use Plack::App::unAPI::Impl;
use Plack::Request;

use parent 'Exporter';
our @EXPORT = qw(unAPI wrAPI);

## no critic
sub unAPI(@) { 
    Plack::App::unAPI::Impl->new(@_)
}
## use critic

sub wrAPI {
    my ($code, $type, %about) = @_;

    # TODO: error response in corresponding content type

    my $app = sub {
        my $id = Plack::Request->new(shift)->param('id') // '';

        my $obj = $code->( $id ); # look up object

        return defined $obj
            ? [ 200, [ 'Content-Type' => $type ], [ $obj ] ]
            : [ 404, [ 'Content-Type' => 'text/plain' ], [ 'not found' ] ];
    };

    return [ $app => $type, %about ];
}

1;

=head1 SYNOPSIS

Create C<app.psgi> like this:

    use Plack::App::unAPI;

    my $get_json = sub { my $id = shift; ...; return $json; };
    my $get_xml  = sub { my $id = shift; ...; return $xml; };
    my $get_txt  = sub { my $id = shift; ...; return $txt; };

    unAPI
        json => wrAPI( $get_json => 'application/json' ),
        xml  => wrAPI( $get_xml  => 'application/xml' ),
        txt  => wrAPI( $get_txt  => 'text/plain' );

The function C<wrAPI> facilitates definition of PSGI apps that serve resources
in one format, based on HTTP query parameter C<id>. One can also use custom
PSGI apps:

    use Plack::App::unAPI;

    my $app1 = sub { ... };   # PSGI app that serves resource in JSON
    my $app2 = sub { ... };   # PSGI app that serves resource in XML
    my $app3 = sub { ... };   # PSGI app that serves resource in plain text

    unAPI
        json => [ $app1 => 'application/json' ],
        xml  => [ $app2 => 'application/xml' ],
        txt  => [ $app3 => 'text/plain', docs => 'http://example.com' ];

Run for instance by calling C<plackup app.psgi> and retrieve:

    http://localhost:5000/?id=abc&format=json  # calls $app1->($env);
    http://localhost:5000/?id=abc&format=xml   # calls $app2->($env);
    http://localhost:5000/?id=abc&format=txt   # calls $app3->($env);
    http://localhost:5000/                     # returns list of formats
    http://localhost:5000/?format=xml          # returns list of formats
    http://localhost:5000/?id=abc              # returns list of formats


PSGI applications can be created as subclass of L<Plack::Component> or as
simple code reference:


=head1 DESCRIPTION

Plack::App::unAPI implements an L<unAPI|http://unapi.info> server as L<PSGI>
application. The HTTP request is routed to different PSGI applications based on
the requested format. An unAPI server receives two query parameters via HTTP
GET:

=over 4

=item id

a resource identifier to select the resource to be returned.

=item format

a format identifier. If no (or no supported) format is specified, a list of
supported formats is returned as XML document.

=back

=method new ( %formats [, _ => { %options } ] )

To create a server object you must provide a list of mappings between format
names and PSGI applications to serve requests for the particular format. Each
application is wrapped in an array reference, followed by its MIME type and
optional information fields about the format. So the general form is:

    format => [ $app => $type, %about ]

The following optional information fields are supported:

=over

=item docs

An URL of a document that describes the format

=item always

By default, the format list with HTTP status code 300 is returned if unless
both, format and id have been supplied. If 'always' is set to true, an empty
identifier will also be routed to the format's application.

=item quality

A number between 0.000 and 1.000 that describes the "source quality" for
content negotiation. The default value is 1.

=item encoding

One or more content encodings, for content negotiation. Typical values are
C<gzip> or C<compress>.

=item charset

The charset for content negotiation (C<undef> by default).

=item language

One or more languages for content negotiation (C<undef> by default).

=back

General options for all formats can be passed with the C<_> field (no format
can have the name C<_>).

By default, the result is checked to be valid PSGI (at least to some degree)
and errors in single applications are catched - in this case a response with
HTTP status code 500 is returned.

=method unAPI ( %formats )

The C<unAPI> keyword as constructor alias is exported by default. To prevent
exporting, include this module via C<use Plack::App::unAPI ();>.

=method wrAPI ( $code, $type, [ %about ] )

This method returns an array reference to be passed to the constructor. The
first argument must be a simple code reference that gets called with C<id> as
only parameter. If its return value is C<undef>, a 404 response is returned.
Otherwise the code reference must return a serialized byte string (NO unicode
characters) that has MIME type C<$type>. To give an example:

    sub get_json { my $id = shift; ...; return $json; }

    # short form:
    my $app = wrAPI( \&get_json => 'application/json' );

    # equivalent code:
    my $app = [
        sub {
            my $id   = Plack::Request->new(shift)->param('id') // '';
            my $json = get_json( $id );
            return defined $json
                ? [ 200, [ 'Content-Type' => $type ], [ $json ] ]
                : [ 404, [ 'Content-Type' => 'text/plain' ], [ 'not found' ] ];
        } => 'application/json' 
    ];
    
=method formats ( [ $id [, $header ] ] )

Returns a PSGI response with status 300 (Multiple Choices) and an XML document
that lists all formats. The optional header argument has default value
C<< <?xml version="1.0" encoding="UTF-8"?> >>.

=method variants

Returns a list of content variants to be used in L<HTTP::Negotiate>. The return
value is an array reference of array references, each with seven elements:
format name, source quality (qs), type, encoding, charset, language, and size.
The list is sorted by format name.  The return value for the example given
above would be:

    [
        ['json','1','application/json',undef,undef,undef,0],
        ['txt','1','text/plain',undef,undef,undef,0],
        ['xml','1','application/xml',undef,undef,undef,0]
    ]

=head1 SEE ALSO

=over

=item

L<Plack::Middleware::Negotiate>

=item

L<http://unapi.info>

=item

Chudnov et al. (2006): I<Introducing unAP>. In: Ariadne, 48,
<http://www.ariadne.ac.uk/issue48/chudnov-et-al/>.

=back

=cut
