package Module::Packaged::Report;
use strict;
use warnings;

use Module::Packaged;
use HTML::Template;
use File::Spec;
use File::Path   qw(mkpath);

use Data::Dumper qw(Dumper);

our $VERSION = '0.01';


sub new {
    my ($class, %opts) = @_;
    usage() if $opts{help};
    usage() if not ($opts{test} xor $opts{real});

    my $self = bless {}, $class;
    $self->{opts} = \%opts;
    $self->{p} = Module::Packaged->new();
    $self->{_timestamp} = time;
    return $self;
}

sub _timestamp {
    my ($self) = @_;
    return scalar localtime $self->{_timestamp};
}

sub _list_packages {
    my ($self) = @_;
    if ($self->{opts}{test}) {
        return qw(AcePerl Acme-Buffy CGI DBD-Pg DBI Spreadsheet-ParseExcel);
    } else {
        return sort keys %{ $self->{p}{data} };
    }
}

sub generate_html_report {
    my ($self) = @_;

    my $dir = $self->_dir;
    mkpath $dir;

    $self->_save_style;

    my @letters = ('A'..'Z');
    foreach my $letter (@letters) {
        $self->_generate_report_for_letter($letter);
    }

    my $template = $self->_index_tmpl();
    my $t = HTML::Template->new_scalar_ref(\$template, die_on_bad_params => 1);
    my @letters_hashes = map {{letter => $_}} @letters;
    $t->param(letters      => \@letters_hashes);
    $t->param(footer        => $self->_footer());

    my $filename = File::Spec->catfile($self->_dir, "index.html");
    open my $fh, '>', $filename  or die "Could not open '$filename' $!";
    print {$fh} $t->output;
}


sub _generate_report_for_letter {
    my ($self, $letter) = @_;

    my @module_names = grep {/^$letter/i} $self->_list_packages;

    my @distros;
    my %packagers; # we are only interested in the keys here
    foreach my $name (@module_names) {
        my $dists = $self->{p}->check($name);
        next if 1 >= keys %$dists; # skip modules that are only on CPAN
        $dists->{name} = $name;
        push @distros, $dists;
        %packagers = (%packagers, %$dists);
        #print Dumper $dists;
    }
    my @packagers = map {{name => $_}} sort keys %packagers;
    

    my $template = $self->_report_tmpl();
    my $t = HTML::Template->new_scalar_ref(\$template, die_on_bad_params => 1);
    #$t->param(packagers    => \@packagers);
    $t->param(distros      => \@distros);
    $t->param(footer        => $self->_footer());

    my $filename = File::Spec->catfile($self->_dir, "$letter.html");
    open my $fh, '>', $filename  or die "Could not open '$filename' $!";
    print {$fh} $t->output;
}

sub _footer {
    my ($self) = @_;
    
    my $template = $self->_footer_tmpl();
    my $t = HTML::Template->new_scalar_ref(\$template, die_on_bad_params => 1);
    $t->param(timestamp    => $self->_timestamp);
    $t->param(mp_version   => $Module::Packaged::VERSION);
    $t->param(mpr_version  => $VERSION);
    return $t->output;
}

 
sub _dir {
    my ($self) = @_;
    return $self->{opts}{dir} || './report';
}

# for the time we might generate the column titles
#<tr>
#  <td></td>
#  <TMPL_LOOP packagers>
#  <td><TMPL_VAR name></td>
#  </TMPL_LOOP>
#</tr>

sub _index_tmpl {
    return <<'END_TMPL';
<html>
<head>
  <title>CPAN Modules in Distributions</title>
  <link rel="stylesheet" type="text/css" href="style.css" /> 
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
  <meta http-equiv="Content-Style-Type" content="text/css" />
</head>
<body>
<center><h1>CPAN Modules in Distributions</h1></center>
Modules starting with letter
<TMPL_LOOP letters>
  <a href="<TMPL_VAR letter>.html"><TMPL_VAR letter></a>&nbsp;
</TMPL_LOOP>
<p>
Wishes: 
<ul>
 <li>Include Sun Solaris, AIX, HP-UNIX etc</li>
 <li>Separate Debian stable and testing</li>
 <li>Ubuntu (separated to its versions and also universe and backport reported separately)</li>
 <li>ACtiveState distributions</li>
</ul>
</p>

<TMPL_VAR footer>
</body>
</html>
END_TMPL

}

sub _save_style {
    my ($self) = @_;

    my $filename = File::Spec->catfile($self->_dir, "style.css");
    open my $fh, '>', $filename or die $!;
    print {$fh} <<'END_CSS';
<style type="text/css"> 
 
first_one_is_not_seen_by_firefox { 
} 
 
h1 { 
    color: #000000; 
    text-align: center; 
} 
 
body { 
    background-color: #FFFFFF; 
} 
table {
    border-width: 1px;
    border-style: solid;
}
td {
    border-width: 1px;
    border-style: solid;
}
</style>

END_CSS

}


sub _report_tmpl {
    return <<'END_TMPL';
<html>
<head>
  <title>CPAN Modules in Distributions</title>
  <link rel="stylesheet" type="text/css" href="style.css" /> 
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
  <meta http-equiv="Content-Style-Type" content="text/css" />
</head>
<body>
<h1>CPAN Modules in Distributions</h1>
<a href="index.html">index</a>
<table>
<tr><td></td>
    <td>CPAN</td>
    <td>Debian</td>
    <td>Fedora</td>
    <td>FreeBSD</td>
    <td>Mandrake</td>
    <td>OpenBSD</td>
    <td>Suse</td>
<TMPL_LOOP distros>
  <tr>
    <td><TMPL_VAR name></td>
    <td><TMPL_VAR cpan></td>
    <td><TMPL_VAR debian></td>
    <td><TMPL_VAR fedora></td>
    <td><TMPL_VAR freebsd></td>
    <td><TMPL_VAR mandrake></td>
    <td><TMPL_VAR openbsd></td>
    <td><TMPL_VAR suse></td>
  </tr>
</TMPL_LOOP>
</table>

<TMPL_VAR footer>

</body>
</html>
END_TMPL

}

sub _footer_tmpl {
    return <<'END_TMPL';
<p>
Report generated on <TMPL_VAR timestamp> 
using <a href="http://search.cpan.org/dist/Module-Packaged-Report">Module::Packaged::Report</a> 
version <TMPL_VAR mpr_version>
and <a href="http://search.cpan.org/dist/Module-Packaged">Module::Packaged</a> version <TMPL_VAR mp_version>. 
Patches to both modules are welcome by the respective authors.
</p>
END_TMPL

}


sub usage {
    print <<"USAGE";
Usage: $0
            --test            test run using small number of modules  
            --real            real run
                              You have to provide either test or real

            --dir DIR         name of the directory where the reports are generated (defaults to ./report)

            --help            this help
USAGE

    exit;
}


=head1 NAME

Module::Packaged::Report - Generate report upon packages of CPAN distributions

=head1 SYNOPSIS

Run the create_package_report.pl script that comes with the module.

=head1 DESCRIPTION

Using L<Module::Package> to fetch the collected data.

Create table of CPAN modules vs. Distributions (e.g. Linux distributions, Solaris compiled packages etc)
that will show for each module and distro which version (if any) of the CPAN module is available 
for that distro in it standard packaging system.

=head1 METHODS

=head2 new

 my $mpr = Module::Packaged::Report->new(%OPTIONS);

 %OPTIONS can be 

 test => 1   or  real => 1

 help => 1 to get help

 dir => /path/to/dir

  
=head2 generate_html_report;

 $mpr->generate_html_report;


=head1 TODO

Add pages for the individual module authors, for each one summarizing all of 
the modules she maintains.

Coloring, so it will be obvious which distribution carries the latest version and 
which one has a huge? gap.

Total number of modules for each distro.

=head1 See also

L<Parse::Debian::Packages> L<Debian::Package::HTML>

=head1 COPYRIGHT

Copyright (c) 2007 Gabor Szabo. All rights reserved. This program is
free software; you can redistribute it and/or modify it under the same
terms as Perl itself.

=head1 AUTHOR

Gabor Szabo <gabor@pti.co.il>

=cut

1;

