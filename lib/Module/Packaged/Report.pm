package Module::Packaged::Report;
use strict;
use warnings;

use Module::Packaged;
use HTML::Template;
use File::Spec;
use File::Path   qw(mkpath);
use Parse::CPAN::Packages;
use App::Cache;

use Data::Dumper qw(Dumper);

our $VERSION = '0.02';

sub new {
    my ($class, %opts) = @_;
    usage() if $opts{help};
    usage() if not ($opts{test} xor $opts{real});

    my $self = bless {}, $class;
    $self->{opts} = \%opts;
    $self->{p} = Module::Packaged->new();
    $self->{_timestamp} = time;

    my $cache = App::Cache->new({ ttl => 60 * 60 });
    my $data = $cache->get_url('http://www.cpan.org/modules/02packages.details.txt.gz');
    $self->{pcp} = Parse::CPAN::Packages->new($data);

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
    mkpath (File::Spec->catfile($dir, 'letters'));
    mkpath (File::Spec->catfile($dir, 'distros'));
    mkpath (File::Spec->catfile($dir, 'authors'));

    $self->_save_style;

    my @letters = ('A'..'Z');
    foreach my $letter (@letters) {
        $self->_generate_report_for_letter($letter);
    }

    my @letters_hashes = map {{letter => $_}} @letters;
    $self->create_file(
            template => $self->_index_tmpl(),
            filename => File::Spec->catfile($self->_dir, "index.html"),
            params => {
                letters      => \@letters_hashes,
                footer        => $self->_footer(),
                %{ $self->{count} },
            },
    );

    # per distribution reports
    foreach my $distro (keys %{ $self->{distros} }) {
        #print "$distro\n";
        my $name = $distro eq 'mandrake' ? 'mandriva' : $distro;

        $self->create_file(
            template => $self->_modules_in_distro_report_tmpl,
            filename => File::Spec->catfile($self->_dir, 'distros', "$name.html"),
            params => {
                distro  => ucfirst($name),
                modules => $self->{distros}{$distro},
            },
        );
    }

    foreach my $cpanid (keys %{ $self->{authors} }) {
        $self->create_file(
            template => $self->_report_tmpl,
            filename => File::Spec->catfile($self->_dir, 'authors', "$cpanid.html"),
            params => {
                distros      => $self->{authors}{$cpanid},
                footer       => $self->_footer(),
            },
        );
    }
    my @cpanids = map {{cpanid => $_}} sort keys %{ $self->{authors} };
    $self->create_file(
        template => $self->_authors_index_tmpl(),
        filename => File::Spec->catfile($self->_dir, 'authors', "index.html"),
        params => {
            ids      => \@cpanids,
            footer   => $self->_footer(),
        },
    );
}


sub _generate_report_for_letter {
    my ($self, $letter) = @_;

    my @module_names = grep {/^$letter/i} $self->_list_packages;

    my @distros;
    my %packagers; # we are only interested in the keys here
    foreach my $dash_name (@module_names) {
        my $dists = $self->{p}->check($dash_name);
        my $name = $dash_name;
        $name =~ s/-/::/g;

        $self->{count}{cpan}++;
        next if 1 >= keys %$dists; # skip modules that are only on CPAN

        # collect data for list of modules in a single distro
        foreach my $distro (keys %$dists) {
            $self->{count}{$distro}++;
            next if $distro eq 'cpan';
            push @{ $self->{distros}{$distro} }, {
                name    => $name,
                version => $dists->{$distro},
                cpan    => $dists->{cpan},
            };
        }
        $dists->{name} = $name;
        push @distros, $dists;

        my $m = $self->{pcp}->package($name);
        if ($m) {
            my $d = $m->distribution;
            push @{ $self->{authors}{uc $d->cpanid} }, $dists;
        } else {
            warn "No package for '$name'\n";
        }

        %packagers = (%packagers, %$dists);
        #print Dumper $dists;
    }
    my @packagers = map {{name => $_}} sort keys %packagers;
    

    $self->create_file(
            template => $self->_report_tmpl(),
            filename => File::Spec->catfile($self->_dir, 'letters', "$letter.html"),
            params => {
                #packagers    => \@packagers,
                distros      => \@distros,
                footer       => $self->_footer(),
            },
    );
}

sub create_file {
    my ($self, %args) = @_;

    my $t = HTML::Template->new_scalar_ref(\$args{template}, die_on_bad_params => 1);
    $t->param(%{ $args{params} });
    open my $fh, '>', $args{filename}  or die "Could not open '$args{filename}' $!";
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

sub _authors_index_tmpl {
    return <<'END_TMPL';
<html>
<head>
  <title>CPAN Modules in Distributions per author</title>
  <link rel="stylesheet" type="text/css" href="../style.css" /> 
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
  <meta http-equiv="Content-Style-Type" content="text/css" />
</head>
<body>
<center><h1>CPAN Modules in Distributions per author</h1></center>
<p>
<a href="../index.html">index</a>
<p>
<TMPL_LOOP ids>
  <a href="<TMPL_VAR cpanid>.html"><TMPL_VAR cpanid></a><br />
</TMPL_LOOP>
<TMPL_VAR footer>
</body>
</html>
END_TMPL

}
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
  <a href="letters/<TMPL_VAR letter>.html"><TMPL_VAR letter></a>&nbsp;
</TMPL_LOOP>
<p>
<a href="authors/">Authors</a>
<p>
Total number of modules in each distribution:
<table>
<tr>
    <td>CPAN</td>
    <td>Debian</td>
    <td>Fedora</td>
    <td>FreeBSD</td>
    <td>Mandriva</td>
    <td>OpenBSD</td>
    <td>Suse</td>
<tr>
    <td><TMPL_VAR cpan></td>
    <td><a href="distros/debian.html"><TMPL_VAR debian></a></td>
    <td><a href="distros/fedora.html"><TMPL_VAR fedora></a></td>
    <td><a href="distros/freebsd.html"><TMPL_VAR freebsd></a></td>
    <td><a href="distros/mandriva.html"><TMPL_VAR mandrake></a></td>
    <td><a href="distros/openbsd.html"><TMPL_VAR openbsd></a></td>
    <td><a href="distros/suse.html"><TMPL_VAR suse></a></td>
</tr>
</table>

<p>
Wishes: 
<ul>
 <li>Include Ubuntu, RedHat, Gentoo, Sun Solaris, AIX, HP-UNIX etc</li>
 <li>Separate Debian stable and testing</li>
 <li>Separate the report for standard, universe and backport repositories</li>
 <li>Include ActiveState distributions</li>
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
    text-align: center;
}
.name {
    text-align: left;
}
</style>

END_CSS

}

sub _modules_in_distro_report_tmpl {
    return <<'END_TMPL';
<html>
<head>
  <title>CPAN Modules in <TMPL_VAR distro></title>
  <link rel="stylesheet" type="text/css" href="../style.css" /> 
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
  <meta http-equiv="Content-Style-Type" content="text/css" />
</head>
<body>
<h1>CPAN Modules in <TMPL_VAR distro></h1>
<a href="../index.html">index</a>
<table>
<tr><td>Name</td>
    <td>Version</td>
    <td>Latest on CPAN</td>
<TMPL_LOOP modules>
  <tr>
    <td class="name"><TMPL_VAR name></td>
    <td><TMPL_VAR version></td>
    <td><TMPL_VAR cpan></td>
  </tr>
</TMPL_LOOP>
</table>

<TMPL_VAR footer>

</body>
</html>
END_TMPL

}



sub _report_tmpl {
    return <<'END_TMPL';
<html>
<head>
  <title>CPAN Modules in Distributions</title>
  <link rel="stylesheet" type="text/css" href="../style.css" /> 
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
  <meta http-equiv="Content-Style-Type" content="text/css" />
</head>
<body>
<h1>CPAN Modules in Distributions</h1>
<a href="../index.html">index</a>
<table>
<tr><td></td>
    <td>CPAN</td>
    <td>Debian</td>
    <td>Fedora</td>
    <td>FreeBSD</td>
    <td>Mandriva</td>
    <td>OpenBSD</td>
    <td>Suse</td>
<TMPL_LOOP distros>
  <tr>
    <td class="name"><TMPL_VAR name></td>
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
Patches to both modules are welcome by the respective authors. Subversion repository of 
<a href="http://svn1.hostlocal.com/szabgab/trunk/Module-Packaged-Report/">Module-Packaged-Report</a>
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

