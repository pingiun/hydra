package Hydra::Plugin::GithubDeploys;

use strict;
use parent 'Hydra::Plugin';
use HTTP::Request;
use JSON;
use LWP::UserAgent;
use Hydra::Helper::CatalystUtils;
use List::Util qw(max);

sub isEnabled {
    my ($self) = @_;
    return defined $self->{config}->{githubdeploys};
}

sub buildFinished {
    my ($self, $build, $dependents) = @_;
    my $cfg = $self->{config}->{githubdeploys};
    my @config = defined $cfg ? ref $cfg eq "ARRAY" ? @$cfg : ($cfg) : ();
    my $ua = LWP::UserAgent->new();
    my $githubEndpoint = $self->{config}->{'github_endpoint'} // "https://api.github.com";

    my $jobName = showJobName $build;

    foreach my $conf (@config) {
        next unless $jobName =~ /^$conf->{jobs}$/;

        my $flake;
        $flake = $b->jobset->flake;
        my $rev;

        if ($flake =~ /([0-9a-f]{40})/) {
            $rev = $1;
        } else {
            $flake = getLatestFinishedEval($b->jobset)->flake;
            $flake =~ /([0-9a-f]{40})/;
            $rev = $1;
        }

        next unless $rev;

        $flake =~ m!github(?:.com)?[:/]([^/]+)/([^/]+?)(?:(?:/|\?).*)$!;
        my $owner = $1;
        my $repo = $2;

        my $body = encode_json({
            ref => $rev,
            auto_merge => JSON::true,
            payload => encode_json({flake => $flake}),
            environment => $build->get_column('job'),
            description => "Deployment after hydra build finished",
        });

        my $url = "${githubEndpoint}/repos/$owner/$repo/deployments";
        my $req = HTTP::Request->new('POST', $url);
        $req->header('Content-Type' => 'application/json');
        $req->header('Accept' => 'application/vnd.github.v3+json');
        my $authorization = $self->{config}->{github_authorization}->{$owner} // $conf->{authorization};
        my $token = read_file("/etc/hydra/authorization/$authorization");
        $token =~ s/\s+//;
        $req->header('Authorization' => "token $token");

        $req->content($body);
        my $res = $ua->request($req);
    }
}

1;
