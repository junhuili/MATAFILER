#!/usr/bin/env perl
#parseBlastFunct.pl /g/bork5/hildebra/data/Ach_proteins/res/DiaAssignment.txt [DB] [mode]
#mode == 0: just parse & report sum stat; 1=report per gene primary DB; 2=report per gene all levels ==2 check for all files present
use warnings;
use strict;
use FileHandle;

use Mods::TamocFunc qw(sortgzblast readTabbed uniq);
use Mods::GenoMetaAss qw(gzipwrite gzipopen);
use Mods::IO_Tamoc_progs qw(getProgPaths );
use Getopt::Long qw( GetOptions );


sub main;
sub readGene2COG; sub readNogKingdom;
sub readCOGdef;
sub readGene2KO;sub readKeggTax;
sub check_files; sub remove_file;
sub writeAllTable;
sub readMohTax;
sub combineBlasts;
sub bestBlHit;
sub help;
sub readCzySubs;
sub eggMap_interpret;
my $emBin = getProgPaths("emapper");




my $blInf = "";#$ARGV[0];
my $mode = 0;#ARGV[3]
my $DBmode = "NOG";#$ARGV[1];
my $quCovFrac = 0; #how much of the query needs to be covered?
my $noHardCatCheck = 0; #select for the hit with KO assignment rather than the real best hit (w/o KO assignment)

#$DBmode = uc $DBmode;
my $minBLE= 1e-7;#ARGV[2]
my $minScore=0;#min required bit score
my $minAlLen = 20; #my $minPidGlobal = 40;
my $tmpD="";#$ARGV[6]
my $DButil = "";#$ARGV[5];
my $lengthF = "";#$ARGV[4];
my $reportEggMapp=0; #do eggNOG mapper?
my $ncore = 4;
my $writeSumTbls = 1; #report all the higher level stats?
my $percID = 30;
my $Card_leniet = 1; #take more CARD hits: eval^(1/$Card_leniet)
my $calcGL = 1;
my $noTax=0;

die "no input args!\n" if (@ARGV == 0 );
GetOptions(
	"help|?" => \&help,
	"i=s"      => \$blInf,
	"DB=s"      => \$DBmode,
	"mode=i"      => \$mode,#0=normal, 1=normal and print per gene anno, 2=file check 4=remove outputfile
	"eval=f"      => \$minBLE,
	"minBitScore=f" => \$minScore,
	"minAlignLen=i"      => \$minAlLen,
	"minPercSbjCov=f"      => \$quCovFrac,
	"tmp=s"      => \$tmpD,
	"DButil=s"	=> \$DButil,
	"LF=s"	=> \$lengthF,
	"lenientCardAssignments=i" => \$Card_leniet,
	"eggNOGmap=i"	=> \$reportEggMapp,
	"summaryTbls=i" => \$writeSumTbls,
	"calcGeneLengthNorm=i" => \$calcGL,
	"singleSpecies=i" => \$noTax,
	"CPU=i" => \$ncore,
	"percID=i" => \$percID, #percent id similiarity, from 0 - 100
) or die("Error in command line arguments\n");

die "Database mode requires -tmp -minAlignLen -LF\n" if ( ($mode != 4 && $mode != 3) && ( $tmpD eq "" || $lengthF eq "" ) );
#die "$tmpD XX\n";
$reportEggMapp=0 if ($DBmode ne "NOG" );


my %DBlen;
if ($lengthF ne "" ){#read the length of DB proteins
	my @spl = split /,/,$lengthF;
	foreach my $lF2 (@spl){
		open I,"<$lF2" or die "length file $lF2 no present!\n";
		while (my $l = <I>){
			chomp $l;
			my @spl = split /\t/,$l;
			$DBlen{$spl[0]} = int $spl[1];
		}
		close I;
	}
	print "read length DB\n";
}

$blInf = sortgzblast($blInf,$tmpD) unless ($mode == 3 || $mode == 4);


#die "$blInf";

my $bl2dbF ;
my $cogDefF ;
my $NOGtaxf ;
my $KEGGlink ;
my $KEGGtaxDb ;
if ($DButil ne ""){
	 $bl2dbF = "$DButil/NOG.members.tsv";
	 $cogDefF = "$DButil/NOG.annotations.tsv";
	 $NOGtaxf = "$DButil/all_species_data.txt";
	 $KEGGlink = "$DButil/genes_ko.list";
	$KEGGtaxDb = "$DButil/kegg.tax.list";

}

$blInf =~ m/(.*)\/([^\/]+$)/;
my $inP = $1; my $inF = $2;
#die "$inP\t$inF\n";

my @blRes;
my @kgdOpts = qw (0 1 2 3);
my @kgdName = ("Bacteria","Archaea","Eukaryota","Fungi");
my @kgdNameShrt = ("BAC","ARC","EUK","FNG");
#which best blast decide algo to use..
my $scomode = 0; my $emode = 1;
my @normMethods = ("cnt");
if ($calcGL){push (@normMethods,"GLN");}
my $czyEuk =2; my $czyFungi=5;
my %czyTax;my %czySubs;
my @aminBLE = split /,/,$minBLE;
#my @aminPID = (40,45,50,55,60,65,70,75,80,85,90,95);
#@aminBLE = ("1e-9") x scalar(@aminPID);
my @aminPID = ($percID) x scalar(@aminBLE);

my %NOGkingd ; my %KEGGtax;
my %COGdef ;my %g2COG ; my %c2CAT ; 
my %cardE; my %cardFunc; my %cardName;
my $tabCats = 0; my $cazyDB = 0; my $ACLdb = 0; my $KGMmode=0;
if ($mode == 3 || $mode == 4){ #scan for all reads finished
} elsif ( $DBmode eq "KGB" || $DBmode eq "KGE" || $DBmode eq "KGM"){
	print "Reading KEGG DBs..\n";
	my ($hr1) = readGene2KO($KEGGlink);
	%c2CAT = %{$hr1};
	#my @tmp = keys %c2CAT; die "$tmp[0] $tmp[1] $tmp[2]\n";
	@kgdOpts = qw (3); $tabCats = 2;
	if ($DBmode eq "KGB"){ @kgdName = ("","","","Bacteria");@kgdNameShrt = ("","","","BAC") ;}
	if ($DBmode eq "KGE"){ @kgdName = ("","","","Eukaryotes");@kgdNameShrt = ("","","","EUK") ;}
	if ($DBmode eq "KGM"){ @kgdName = ("Prokayotes","Eukaryotes","","Unclassified");@kgdNameShrt = ("BAC","EUK","","UNC") ; 
		@kgdOpts = qw (0 1 3); $KGMmode=1; 
	}
	$hr1 = readKeggTax($KEGGtaxDb);
	%KEGGtax = %{$hr1};
} elsif ( $DBmode eq "NOG"){
	print "Reading NOG DBs..\n";
	my ($hr1,$hr2) = readGene2COG($bl2dbF);
	%g2COG = %{$hr1}; %c2CAT = %{$hr2};
	$hr1 = readCOGdef($cogDefF);
	%COGdef = %{$hr1}; $tabCats = 1;
	%NOGkingd = readNogKingdom($NOGtaxf);
} elsif ($DBmode eq "CZy"){
	@kgdOpts = qw (0 1 2 3 4 5);
	my $hr = readMohTax($DButil."/MohCzy.tax");
	%czyTax = %{$hr};
	$hr = readCzySubs("$DButil/cazy_substrate_info.txt");
	%czySubs = %{$hr};
	$czyEuk =2; $czyFungi=5;
	@kgdName = ("Bacteria","Archaea","Eukaryota","unclassified","CBM","Fungi");
	@kgdNameShrt = ("BAC","ARC","EUK","UNC","CBM","FNG");
	$cazyDB = 1;
	$tabCats=3;
	print "CAZy database\n";
} elsif ($DBmode eq "ACL"){
	@kgdOpts = qw (3);
	$czyEuk =2; $czyFungi=5;
	@kgdName = ("Plasmid","Prophage","Virus","unclassified");
	@kgdNameShrt = ("PLA","PRO","VIR","UNC");
	$ACLdb = 1;
	print "aclame database\n";
} elsif ($DBmode eq "ABRc"){
	@kgdOpts = qw (3);
	@kgdName = ("","","","All");
	@kgdNameShrt = ("","","","ALL");
	print "ABR Card database\n";
	my $hr = readTabbed($DButil."cardEval.txt");
	%cardE = %{$hr};
	$hr = readTabbed($DButil."cardClass.txt");
	%cardFunc = %{$hr};
	$hr = readTabbed($DButil."cardName.txt");
	%cardName = %{$hr};
	$tabCats=5;
} else{
	@kgdOpts = qw (3);
	@kgdName = ("","","","All");
	@kgdNameShrt = ("","","","ALL");
	print "Non - NOG DB\n";
}

if ($noTax){
	@kgdOpts = qw (3);
	@kgdName = ("","","","All");
	@kgdNameShrt = ("","","","ALL");
	print "no Tax info being used\n";
}


#read DB file
my $readLim = 1000000; my $lcnt=0;my $lastQ=""; my $stopInMiddle=0; my $reportGeneCat=0;
my $mergeDiaHit =0; 
my %COGhits; my %CAThits; my %GENEhits; my $O2; my %OEM;
my %emFiles ; my %emFilesFinal;
for (my $i=0; $i<@aminBLE ; $i++){$COGhits{$i} = {}; $CAThits{$i} = {}; $GENEhits{$i} = {};}
if ($mode == 0 || $mode==1 || $mode == 2){ #mode1 = write gene assignment, mode 2: write for each gene higher lvl cat
	#die "$blInf\n";
	$reportGeneCat = $mode if ($mode >= 1);
	#insert here KEGG BAC ? EUK fix
	if ($KGMmode && !-e $blInf){
		#zcat dia.KGB.blast.gz dia.KGE.blast.gz | sort | gzip > dia.KGM.blast.gz
		my $KGBf = $blInf; my $KGEf = $blInf; 
		$KGBf =~ s/KGM/KGB/; $KGEf =~ s/KGM/KGE/;
		my $cmd = "zcat $KGBf $KGEf | sort | gzip > $blInf\n";
		system $cmd."\n";
	}
	
	my ($I,$OK) = gzipopen($blInf,"diamond output file [in]",1); 
	my $OK2;
	($O2,$OK2) = gzipwrite($blInf."geneAss","gene cat file [out]",1) if ($reportGeneCat);
	if ($reportEggMapp){
		system "mkdir -p $tmpD" unless (-d $tmpD);
		foreach (my $j=0;$j<@kgdOpts;$j++){
			my $kk = $kgdOpts[$j];
			next if ($kk eq "");
			
			$emFilesFinal{$kk} = "$blInf.emap.$kgdNameShrt[$j].table";
			$emFiles{$kk} = "$tmpD/$DBmode.emap.$kgdNameShrt[$j].table";
			print "$tmpD/$DBmode.emap.$kgdNameShrt[$j].table\n";
			open $OEM{$kk},">$emFiles{$kk}" or die "Can't open $tmpD/$DBmode.emap.$kgdNameShrt[$j].table\n";
	}}
	#die;
	
	my @splSave;
	
	while (1){
		my %wordv1; my %wordv2;
		while (my $line = <$I>){
			chomp $line; 
			my @spl = split (/\t/,$line);
			my $query = $spl [0];
			$query =~ s/\/\d$//;
			
#			$lcnt++;
			
			if ($lastQ eq ""){$lastQ = $query;
			} elsif ($lastQ ne $query){
				$stopInMiddle=1;@splSave = @spl;last;
			}
			if (@spl > 10 ){ if ( $spl[0] =~ m/2$/){
				$wordv2{$spl [1]} = \@spl;
				} else {$wordv1{ $spl [1]} = \@spl;}
			}

#			push(@blRes,\@spl);
		}
		#1st combine scores
		my $whX = combineBlasts(\%wordv1,\%wordv2);
		#2nd: sort these, find best hit
		#my $arBhit = bestBlHit($whX); #doesn't need this, this is done in the major routine
		@blRes = values %{$whX};

		#die @blRes."\n";
		#print "Read Assignments..\n";
		for (my $i=0; $i<@aminBLE ; $i++){
			main($aminBLE[$i],$aminPID[$i],$i,$reportEggMapp);
		}
		undef @blRes;
		push(@blRes,\@splSave);
		if ($stopInMiddle==0){last;}
		$lcnt=0;$lastQ="";$stopInMiddle=0;
	}
	close $I;
	close $O2 if ($reportGeneCat);
	if ($reportEggMapp){foreach my $kk (keys %OEM){	close $OEM{$kk}}}
	print"writing Tables\n";
	
	
	if ($writeSumTbls){
		for (my $i=0; $i<@aminBLE ; $i++){
			my $pathXtra = "/CNT_".$aminBLE[$i]."_".$aminPID[$i]."/";
			my $outPath = $inP.$pathXtra;
			writeAllTable($DBmode."parse",$outPath,$aminBLE[$i],$aminPID[$i],$i);#$st1{$i}, $CAThits{$i},$st3{$i});
			#and do eggnog mapping for specific filter parameters
			eggMap_interpret($outPath);
		}
	}
	system "touch $blInf.stone";
	print "Merged $mergeDiaHit Diamond hits from DB\n";
	print "all done\n" if ($mode <3);
	
	exit(0);

	
	
	
} elsif ($mode==3) { #only checks for presence of run
	for (my $i=0; $i<@aminBLE ; $i++){
		my $pathXtra = "/CNT_".$aminBLE[$i]."/";
		unless(check_files($DBmode."parse",$inP.$pathXtra,$aminBLE[$i])){exit(3);}
	}
} elsif ($mode==4) { #removes run

	for (my $i=0; $i<@aminBLE ; $i++){
		my $pathXtra = "/CNT_".$aminBLE[$i]."/";
		remove_file($DBmode."parse",$inP.$pathXtra,$aminBLE[$i]);
	}
} else {die"unkown run mode!!!\n";}

if ($mode ==3){
}

#print "all done\n";
exit(0);

sub splitandadd($ $ $){
	my ($hr,$terms,$shareEffect) = @_;
	return if ($terms eq "" || length($terms)==0);
	my @spl = split /,/,$terms;
	my $val = 1;
	$val = 1/scalar(@spl) if ($shareEffect);
	foreach my $term (@spl){
		${$hr}{$term} += $val;
	}
}

sub writeHashTbl($ $){
	my ($outF,$hr) = @_;
	my %hs = %{$hr};
	open OH,">$outF" or die "Can't open hash out file $outF\n";
	my @kk = sort { $hs{$b} <=> $hs{$a} } keys(%hs);
	foreach my $k (@kk){
		print OH "$k\t$hs{$k}\n";
	}
	close OH;
}

sub eggMap_interpret($){ #higher level annotations with egg nog mapper
	if (!$reportEggMapp){return;}
	my ($outD) = @_;
	die "too many evals chosen" if (@aminBLE > 1 ); #fix that only one eval will be printed...
	my @keys1 = keys %emFiles;
	my $tmpEM = "$tmpD/EMcomb$DBmode.table";
	system "rm -f $tmpEM";
	#run only once on combined file..
	my @emFilesDel;
	foreach my $kk (@keys1){
		push (@emFilesDel,$emFiles{$kk});
		system "cat $emFiles{$kk} >> $tmpEM;";
		system "echo 'split_falk_EM_123\t634498.mru_0149\t0\t1000\n' >> $tmpEM";
		die "$kk entry in emFilesFinal doesn't exist\n" unless (exists($emFilesFinal{$kk}));
		system "rm -f $emFiles{$kk}";
		#last;
	}
	my $oFil = "$tmpD/combEM$DBmode.res"; $oFil =~ s/table//;
	my $cmd = "rm $oFil.1* \n";
	$cmd .= "$emBin -d none --cpu $ncore --no_search --temp_dir $tmpD --no_file_comments --override --no_refine --annotate_hits_table $tmpEM -o $oFil.1\n" ;
	system "$cmd\n";
	print $cmd."\n";
	
	#objects to count on higher level
	my %GOs; my %Kmaps; my %COGcats;
	my $ofCnt = 0;
	#die "@keys1  ".@keys1."\n";
	open O,">$emFilesFinal{$keys1[$ofCnt]}";
	print O "#QueryID\tNOG\tNOGcat\tNOGdescr\tKEGGmap\tGOterms\n";
	open I,"<$oFil.1.emapper.annotations" or die "can't open $oFil.1.emapper.annotations\n";
	while (my $lin = <I>){
		if ($lin =~ m/^#/){next;
		} elsif ($lin =~ m/^split_falk_EM_123\t/){ #split signal to go to next tax lvl
			close O; 
			
			#write out countups in higher levels
			writeHashTbl($outD."eggNogM_GO.txt",\%GOs) if (keys(%GOs)>=1);
			writeHashTbl($outD."eggNogM_KEGG_map.txt",\%Kmaps) if (keys(%Kmaps)>=1);
			writeHashTbl($outD."eggNogM_COG_cats.txt",\%COGcats) if (keys(%COGcats)>=1);
			print "$ofCnt $keys1[$ofCnt] $emFilesFinal{$keys1[$ofCnt]}\n";
			open O,">$emFilesFinal{$keys1[$ofCnt]}" or die "Can't open $emFilesFinal{$keys1[$ofCnt]}\n";
			$ofCnt++;
			next;
		}
		chomp $lin;
		my @spl = split /\t/,$lin;
		my $oStr = "$spl[0]\t";
		my  $Ccat = $spl[10];$Ccat = "" if (!defined $Ccat);
		my $Cdef = $spl[11];$Cdef = "" if (!defined $Cdef);
		my $Kmap = $spl[6]; $Kmap = "" if (!defined $Kmap);
		my $GOterm = $spl[5];$GOterm = "" if (!defined $GOterm);
		if ($spl[8] =~ m/,([^,]+)\@NOG/){
			$oStr .= "\t$1";
			#print $1."\n";
			if ($tabCats==1){
				$Cdef = $COGdef{$1} if (exists($COGdef{$1}));
				$Ccat = $c2CAT{$1} if (exists($c2CAT{$1}));
			} elsif ($tabCats==2){#KEGG
			}
		} else {
			$oStr .= "\t";
		}
		#print "$GOterm , $Kmap , $Ccat\n";
		splitandadd(\%GOs,$GOterm,0);
		splitandadd(\%Kmaps,$Kmap,1);
		splitandadd(\%COGcats,$Ccat,1);
		$oStr.= "\t$Cdef\t$Ccat\t$Kmap\t$GOterm\n";
		print O "$oStr\n";
	}
	close O; close I;
	system "rm -f $tmpEM $oFil.1.emapper.annotations";

	#write hashes out
	#TODO
	if ($ofCnt < @keys1){die "Not enough taxsplits found in eggNogFile ($ofCnt)\n$oFil.1.annotations\n";}
	#system "rm ".join(" ",@emFilesDel)." $oFil.1*";
}

sub remove_file{
	my ($outF,$outD,$minBLE) = @_;
	my $out = $outD."/".$outF;
	system "rm -f $out*" if (-d $outD);
}
sub check_files{
	my ($outF,$outD,$minBLE) = @_;
	my $out = $outD."/".$outF;
	my @srchFls = (#"$out.$DBmode.GENE2$DBmode", #"$out.GENE2$DBmode"."aCAT"
	"$out.$DBmode.$kgdNameShrt[0].gene.cnts","$out.$DBmode.$kgdNameShrt[0].cat.cnts");
	push (@srchFls,"$out.$kgdNameShrt[0].CATcnts") if ( $DBmode eq "NOG");
	foreach (@srchFls) { unless (-e $_.".gz"){print "Fail $_\n";return 0;}}
	return 1;
}

sub writeAllTable(){
	my ($outF,$outD,$minBLE,$minPID,$pos) = @_;#,$hr1,$hr2,$hr3) = @_;
	system "mkdir -p $outD" ;#or die "Failed to create out dir $outD\n";
	my $out = $outD."/".$outF;
	system "rm -f $out*";
	my %COGabundance=%{$COGhits{$pos}}; my %CATabundance=%{$CAThits{$pos}}; my %funHit=%{$GENEhits{$pos}};
	#my %COGabundance=%{$hr1}; my %CATabundance=%{$hr2}; my %funHit=%{$hr3};
	my $cnt = -1;
	foreach my $normMethod (@normMethods){
		$cnt ++;
		foreach my $y (@kgdOpts){
		next if ($kgdName[$y] eq "");
			my @kk; my $O = FileHandle->new;
			if ($tabCats==0){ #MOG CZy etc
				#don't write this for NOGs any longer..
				@kk = sort { $funHit{$normMethod}{$y}{$b} <=> $funHit{$normMethod}{$y}{$a} } keys(%{$funHit{$normMethod}{$y}});
				$O = gzipwrite("$out.$DBmode.$kgdNameShrt[$y].$normMethod.gene.cnts","Dia gene $y Counts");
				#open O,">$out.$DBmode.gene.cnts";
				foreach my $k (@kk){print $O $k."\t".$funHit{$normMethod}{$y}{$k}."\n";}
				close $O;
			}
				
			if ($tabCats != 2 ){#all but KO & CZy
				@kk = sort { $COGabundance{$normMethod}{$y}{$b} <=> $COGabundance{$normMethod}{$y}{$a} } keys(%{$COGabundance{$normMethod}{$y}});
				$O = gzipwrite("$out.$DBmode.$kgdNameShrt[$y].$normMethod.cat.cnts","Dia cat $y Counts");
				#open O,">$out.$DBmode.cat.cnts"; 
				my $cogCnts=0;
				foreach my $k (@kk){print $O $k."\t".$COGabundance{$normMethod}{$y}{$k}."\n";$cogCnts++;}
				close $O;
				print "Total of $cogCnts categories in $kgdName[$y].\n"if ($cnt==0);
			}
			if ($tabCats){ #NOG || KEGG || CZy || ABRc
				#print CATs 
				@kk = sort { $CATabundance{$normMethod}{$y}{$b} <=> $CATabundance{$normMethod}{$y}{$a} } keys(%{$CATabundance{$normMethod}{$y}});
				#print @kk."\n";
				$O = gzipwrite("$out.$kgdNameShrt[$y].$normMethod.CATcnts","Dia NOG cat $y Counts");
				#open O,">$out.CATcnts";
				my $CATcnt =0;
				foreach my $k (@kk){print $O $k."\t".$CATabundance{$normMethod}{$y}{$k}."\n"; $CATcnt ++;  }#else {print "X";} }
				close $O;
				#print "Total of $CATcnt categories: failed $CATfail of ".($CATfail+$CATexist)." assignments\n";
			}
		}
	}
	#sleep(5);
	#is being counted double due to normethod counts

}

#routine accepts a single read/gene hit to several valid targets
#and selects one hit as "best", annotates this hit & summarizes at higher level
sub main(){
	my ($minBLE,$minPid,$pos,$reportEggMappNow)=@_;
	if (@blRes == 0){return;}
	my %COGabundance=%{$COGhits{$pos}}; my %CATabundance=%{$CAThits{$pos}}; my %funHit=%{$GENEhits{$pos}};

#	my %COGabundance=%{$hr1}; my %CATabundance=%{$hr2}; my %funHit=%{$hr3};
	if (!$emode && !$scomode){die "No scoring mode selected!!\n";}
	#print "Scanning $DBmode with an eval of $minBLE\n";
	my $NOGtreat = 0; $NOGtreat = 1 if ($DBmode eq "NOG");
	#my %kgd = %{$kgdHR};
	
	my @tmp = ("");
	@tmp = @{$blRes[0]};
	my $qold=$tmp[0];
	die "Subject length not in length DB : $tmp[1]\n" unless (exists ($DBlen{$tmp[1]}));
	my $SbjLen = $DBlen{$tmp[1]};
	my $COGfail=0; my $CATfail=0; my $totalCOG=0; my $CATexist=0;  my $ii=0;
	
	my $eggNOGmap =0;
	if ($minBLE =~ m/^ENM$/){
		$eggNOGmap = 1; #in this mode just print the "best hit" to a file, that egm can work on later..
	}
	#this routine simply counts up number of hits to COGXX
	
	#while (1){ #don't need this, should only go once over this..
	my $fndCat=0;
	
	#my $arBhit = bestBlHit($whX); 

	my $bestSbj="";my $bestID=0; my $bestAlLen=0;my $bestQuery = ""; my $bestIDever=0;
	my $COGexists=0; 
	my $bestScore = 0; my $CBMmode = 0; my $bestE=1000; my $bestBitScpre=0;
	
	for( ;$ii<@blRes;$ii++){
		#print "@{$blRes[$ii]}[0]\n";
		my ($Query,$Subject,$id,$AlLen,$mistmatches,$gapOpe,$qstart,$qend,$sstart,$send,$eval,$bitSc) = @{$blRes[$ii]};
		#print $eval."\n";
		#sort by eval #changed from bestE -> bestScore
#die "\n".($cardE{$Subject}**(1/$Card_leniet))."\n$cardE{$Subject}\n";
		if ( ($eval <= $minBLE && $bitSc >= $minScore)
					&& ($AlLen >= $minAlLen)
					&& ($id >= $minPid)
					&& ($quCovFrac == 0 || $AlLen > $SbjLen*$quCovFrac) 
					&& (!$fndCat || $noHardCatCheck || exists $c2CAT{$Subject})
					&& ($tabCats!=5 || $eval <= ($cardE{$Subject}**(1/$Card_leniet)) ) #Card
					) {
					#now decide if the hit itself is actually better
					
			if (($bestID -5)< $id && $bestE*10 > $eval &&
					( $id >= ($bestID *0.97) && $id >= $bestIDever*0.9   && ( $AlLen >= $bestAlLen * 1.15 ) )  ||  #length is just better (15%+)
					(   ($id >= $bestID *1.03) && ( $AlLen >= $bestAlLen * 0.9) ) ||#id is just better, while length is not too much off
					$bitSc > $bestBitScpre*0.8){   #convincing score
						
						$fndCat =1; 
						$bestSbj =$Subject; 
						$bestAlLen=$AlLen;$bestE = $eval; $bestQuery = $Query;
						$bestBitScpre=$bitSc;
						$bestID = $id;  
						if ($bestID > $bestIDever){$bestIDever=$bestID;}
			}
		}
		my @tmp;
	}
	#print @blRes ."  $bestSbj $bestQuery\n";
	#print "$ii ". ($ii+1 >= @blRes)." XX\n";
	if ($bestSbj eq ""){return;}
	
	
	#finalize assignment to read
	my $curCOG="-";my $curCat = ""; my $curDef = "";
	my $curKgd = 3; #default always 3.. historic
	my @splC;
	if ($ACLdb || $KGMmode){
		@splC = split /:/,$bestSbj ; $splC[0] = $splC[1] if ($ACLdb);
	} elsif ($cazyDB || $tabCats==0 ) {
		@splC = split /\|/,$bestSbj;
	} 
	if ($noTax){
		;
	} elsif ($cazyDB){
		if ($bestSbj =~ m/bacteria/){$curKgd =0;
		}elsif ($bestSbj =~ m/archaea/) {$curKgd =1;
		}elsif ($bestSbj =~ m/eukaryota/){ $curKgd =2 ;
			if (exists($czyTax{$splC[$#splC]})){$curKgd = $czyTax{$splC[$#splC]} ;}
		}else{ #take Mohs long list
			$curKgd = $czyTax{$splC[$#splC]} if (exists($czyTax{$splC[$#splC]}));
		}
		#else {print $bestSbj." ";}
		#get rid of CBM
		if (0 && $bestSbj =~ m/\|CBM\d+/) {$CBMmode = 1; $curKgd = 4;}
	} elsif ( 0 && $ACLdb){ #cats are too primitive, doesn't need to be split up any further
		#67936 >protein:plasmid  25941 >protein:proph  28277 >protein:vir
		if ($bestSbj =~ m/plasmid/){$curKgd =0;
		}elsif ($bestSbj =~ m/proph/){$curKgd =1;
		}elsif ($bestSbj =~ m/vir/){$curKgd =2;
		}
	} elsif ($KGMmode){
		if (exists($KEGGtax{$splC[0]})){
			$curKgd = $KEGGtax{$splC[0]};
		}  #else {print "X";}
	} elsif ($tabCats == 1){ #NOG
		$bestSbj =~ m/^(\d+)\./; my $taxid = $1;
		if (!exists $NOGkingd{$taxid}){print "Can't find $taxid in ref tax\n";}
		$curKgd = $NOGkingd{$taxid} if (!$CBMmode);
	}
	
	if ($tabCats == 1){
		unless (exists( $g2COG{$bestSbj} )){
			$COGfail++;	return;
		}
		$curCOG = $g2COG{$bestSbj};
		$curDef = $COGdef{$curCOG} if (exists $COGdef{$curCOG});
	}
	if ($reportEggMappNow){
		print  {$OEM{$curKgd}} "$bestQuery\t$bestSbj\t$bestE\t$bestBitScpre\n" ;
	}
	my $lpCnt=0;
	my $score = 1;
	if ($bestQuery =~ m/\/12$/){
		$mergeDiaHit ++ ; $score = 2 ;
	}elsif ($tabCats==5){#ABR CARD
		$curCOG = $cardName{$bestSbj};
	}elsif ($tabCats == 2){ #KEGG
		if (exists $c2CAT{$bestSbj} ){
			$curCat = $c2CAT{$bestSbj}; $CATexist++;
		} else {$CATfail++; return;}
	}elsif ($tabCats==3){  #CAZy
		$curCOG = $splC[0];
	}
	foreach my $normMethod (@normMethods){
		$totalCOG++; $lpCnt++;
		#die "can't find length entry for $bestSbj\n" unless (exists $DBlen{$bestSbj});
		#print $DBlen{$bestSbj}." $normMethod ";
		$score = $bestAlLen / $SbjLen if ($normMethod eq "GLN"); #score for this hit, normed by prot length
		if ($tabCats == 1){ #NOG
			#hash{$_} = $valA for qw(a b c);
			#if (!exists($COGabundance{$normMethod}{$curCOG})){$COGabundance{$normMethod}{$curCOG}{$_}=0 foreach (@kgdOpts);}
			$COGabundance{$normMethod}{$curKgd}{$curCOG}+= $score;
			if (exists($c2CAT{$curCOG})){
				$curCat = $c2CAT{$curCOG};$CATexist++;
				#if (!exists($CATabundance{$normMethod}{$curCat})){$CATabundance{$normMethod}{$curCat}{$_}=0 foreach (@kgdOpts);}
				$CATabundance{$normMethod}{$curKgd}{$curCat} += $score;
			} else {
				$CATfail++;
				#print "Cat unknw for: $curCOG\n" ;
			}
			#print $O "$Query\t$Subject\t$bestID\t$bestE\t$bestAlLen\t$curCOG\t$curCat\t$curDef\n";
			if ($lpCnt==1){
				print $O2 "$bestQuery\t$curCOG\n" if ($reportGeneCat ==1);
				print $O2 "$bestQuery\t$curCOG\t$curCat\t$curDef\n" if ($reportGeneCat ==2);
			}
		
		} elsif ($tabCats == 2){ #KEGG
			$CATabundance{$normMethod}{$curKgd}{$curCat} += $score;
			if ($lpCnt==1 && $curCat ne "" ){
				print $O2 "$bestQuery\t$curCat\n" if ($reportGeneCat  );
			}
		} elsif ($tabCats==5){#ABR CARD
			$COGabundance{$normMethod}{$curKgd}{$curCOG}+= $score;
			my @curCats = split /,/,$cardFunc{$bestSbj};
			foreach my $cCt (@curCats){
				$CATabundance{$normMethod}{$curKgd}{$cCt}+= $score;
			}
			if ($lpCnt==1){
				print $O2 "$bestQuery\t$curCOG\n" if ($reportGeneCat ==1);
				print $O2 "$bestQuery\t$curCOG\t".join(",",@curCats)."\n" if ($reportGeneCat ==2);
			}
		} elsif ($tabCats==3){  #CAZy
			$COGabundance{$normMethod}{$curKgd}{$curCOG}+= $score;
			die "$curCOG\n" unless (exists ($czySubs{$curCOG}));
			my @subs = @{$czySubs{$curCOG}};
			#print "@subs\n";
			foreach my $cCt (@subs){
				#print "$cCt ";
				$CATabundance{$normMethod}{$curKgd}{$cCt}+= $score;
			}
			if ($lpCnt==1){
				print $O2 "$bestQuery\t$curCOG\n" if ($reportGeneCat );
				print $O2 "$bestQuery\t$curCOG\t".join(",",@subs)."\n" if ($reportGeneCat );
			}
			
		} else { #Moh / CAZY / ACL
			$curCOG = $splC[0];
			$COGabundance{$normMethod}{$curKgd}{$curCOG}+= $score;
			if ($lpCnt==1){
				print $O2 "$bestQuery\t$curCOG\n" if ($reportGeneCat );
			}
		}
		#if (!exists($funHit{$normMethod}{$bestSbj})){$funHit{$normMethod}{$bestSbj}{$_}=0 foreach (@kgdOpts); } 
		if ($tabCats == 0){ #don't need this for KEGG and NOG
			$funHit{$normMethod}{$curKgd}{$bestSbj}+= $score;
		}
	}
#		$bestSbj="";$bestE=1000; $bestScore=0;$CBMmode=0;$bestBitScpre=0;
#		$bestSbj="";$bestE=10; $bestScore=0;$CBMmode=0;
	$totalCOG /= 2; $CATfail /= 2;#$COGfail /= 2;
	#if (0&& $DBmode eq "NOG"){
	#	print "Total entries:$totalCOG\nCOG not found: $COGfail, CAT not found: $CATfail\n";
	#} 
	#die;
	#return (\%COGabundance, \%CATabundance, \%funHit);
	$COGhits{$pos} = \%COGabundance; $CAThits{$pos} = \%CATabundance;  $GENEhits{$pos} = \%funHit;

}


sub readCOGdef(){
	my ($inF) = @_;
	open I,"<$inF";
	my %ret;
	while (my $line = <I>){
		chomp $line;
		my ($txx,$COG,$n1,$n2,$cat,$def) = split(/\t/,$line);
		$ret{$COG} = $def;
	}
	close I;
	return \%ret;
}
sub readKeggTax{
	my ($inF) = @_;
	my %ret; my $eukCnt=0; my $proCnt=0;
	open I,"<$inF";
	while (<I>){
		chomp; my @spl = split /\t/;
		my $taxI = 0; 
		if ($spl[1] eq "euka"){$taxI = 1 ; $eukCnt++} else {$proCnt++;}
		$ret{$spl[0]} = $taxI;
	}
	close I;
	print "Euk in KEGG DB = $eukCnt; Pro = $proCnt\n";
	return \%ret;
}
sub readGene2KO(){
	my ($inF) = @_;
	my %c2cat;
	open I,"<$inF";
	print "reading gene -> KO file.. " or die "gene2ko file not present\n";
	while (my $line=<I>){
		chomp $line;
		my ($gn,$KO) = split(/\t/,$line);
		$KO =~ s/^ko://;
		$c2cat{$gn} = $KO;
	}
	print "Done\n";
	close I;
	return (\%c2cat);
}
sub readGene2COG(){
	my ($inF) = @_;
	my %g2c; my %c2cat;
	open I,"<$inF";
	print "reading gene -> COG file.. ";
	while (my $line=<I>){
		chomp $line;
		#NOG     COG5157 253     225     K       9796.ENSECAP00000013089,
		my ($cls,$COG,$p1,$p2,$cat,$genes) = split(/\t/,$line);
		$c2cat{$COG} = $cat;
		my @all = split(/,/,$genes);
		foreach (@all){
			#die "$_ $COG $cat\n";
			$g2c{$_} = $COG;
		}
	}
	print "Done\n";
	close I;
	return (\%g2c,\%c2cat);
}

sub readMohTax(){
	my ($inf) = @_;
	my %ret;
	open I,"<$inf" or die "Could not find Moh tax file at $inf\n";
	while (my $line = <I>){
		chomp $line;
		my @spl = split /\t/,$line;
		
		my $taxI =$czyEuk;#euk code
		$taxI = $czyFungi if ($spl[1] =~ m/fungi/i);
		$ret{$spl[0]} = $taxI;
	}
	close I;
	return \%ret;
}

sub readNogKingdom($){
	my ($inT) = @_;
	my %ret;
	open I,"<$inT" or die "Can't open NOG tax file\n";;
	while (my $line = <I>){
		my $cls = 0; #bacteria
		$cls = 1 if ($line =~ m/Archaea/);
		if ($line =~ m/Eukaryota/){
			$cls = 2;
			$cls =3 if ($line =~ m/Fungi/);
		}
		$line =~ m/^(\d+)\s/;
		$ret {$1} = $cls;
	}
	close I;
	return %ret;
}
sub readCzySubs($){#cazy_substrate_info.txt
	my ($inF) = @_;
	open I,"<$inF" or die "Can't open $inF\n";
	my $cnt =0;
	my %ret;
	my $catsInCzu =0 ;
	my @cats = ("PlantCW","Chitin","AlpGlucans","AnimalCarb","BacterialCW","Fructans","FungalCarbs","Dextran");
	while (<I>){
		$cnt++;
		chomp;
		next if ($cnt==1);
		#	Plant Cell Wall Carbohydrates	Chitin	Alpha-glucans	Animal Carbohydrates	Bacterial Cell Wall Carbohydrates	Fructans	Fungal Carbohydrates	Dextran
		my @entr = split /\t/;
		my $idx = shift @entr;
		my $idx2 = $idx; $idx2 =~ s/Unclassified-// ;
		$idx = $idx2 unless (exists($ret{$idx2}));
		#print "x$idx ";
		my $hits=0;
		for( my $x=0;$x< @entr; $x++){
			if ($entr[$x] eq "YES"){
				push (@{$ret{$idx}}, $cats[$x]);
				$hits++;
				$catsInCzu++;
			}
		}
		if ($hits==0){
			$ret{$idx} = [];
		}
	}
	close I;
	#die "$catsInCzu\n";
	return \%ret;
}

sub combineBlasts($ $){
	my ($wh1,$wh2) = @_;
	my %bl1 = %{$wh1}; my %bl2 = %{$wh2};
	my %ret;
	
	my @allKs = uniq ( keys %bl1, keys %bl2); #
	#die "@allKs\n";
	foreach my $k (@allKs){
		my $ex1 = exists ($bl1{$k});
		unless ($ex1 && exists ($bl2{$k}) ){
			if ($ex1){$ret{$k} = $bl1{$k};
			} else { $ret{$k} = $bl2{$k};}
			next;
		}
		#pair
		#print "pair";
		$k =~ s/\/\d$/\/12/;
		$ret{$k} = $bl1{$k};
		my @hit1 = @{$bl1{$k}};
		my @hit2 = @{$bl2{$k}};
		
		my @sbss1 = sort{ $a <=> $b }(($hit1[8],$hit1[9]));
		my @sbss2 = sort{ $a <=> $b }($hit2[8],$hit2[9]);
		#sort 
		#print "$sbss1[0] > $sbss2[0]\n";
		if ($sbss1[0] > $sbss2[0]){
		#print"X";
			my @tmp = @hit1; @hit1 = @hit2; @hit2 = @tmp;
			@tmp = @sbss1; @sbss1 = @sbss2; @sbss2 = @tmp;
		}
		my @quss1 = sort { $a <=> $b }($hit1[6],$hit1[7]);my @quss2 = sort { $a <=> $b }($hit2[6],$hit2[7]);
		#overlap?
		my $overlap = 0;
		if ($sbss1[1] > $sbss2[0]){ $overlap= ( $sbss1[1] - $sbss2[0]); }#die "${$ret{$k}}[3] = $hit1[3] + $hit2[3] - ( $sbss1[1] - $sbss2[0])\n";}
		${$ret{$k}}[3] = $hit1[3] + $hit2[3] - $overlap; #ALlength
		#print "$sbss1[1] > $sbss2[0] $sbss1[0]  ${$ret{$k}}[3] $overlap\n";
		${$ret{$k}}[2] = ($hit1[2] + $hit2[2] ) /2;#%id
		${$ret{$k}}[11] = ($hit1[11] + $hit2[11]) * (1- $overlap/($hit1[3] + $hit2[3] ) );#bitscore
		${$ret{$k}}[10] = ($hit1[10], $hit2[10])[$hit1[10] > $hit2[10]];  # min($hit1[10] + $hit2[10]);
		#die "@{$ret{$k}}\n";
		#print "$k \n@sbss1 @sbss2\n@hit1\n";
	}
	
	return \%ret;
}

sub bestBlHit($){
	my ($hr) = @_;
	#my $emode=0; my $scomode = 1;
	my %blasts = %{$hr}; my $bestBit=0; my $bestk=""; my $bestScore=0;my $bestID=0; my $bestLen=0; my $bestIDever=0;
	my $k = "";
	foreach$k(keys %blasts){
		#my ($Query,$Subject,$id,$AlLen,$mistmatches,$gapOpe,$qstart,$qend,$sstart,$send,$eval,$bitSc) = ${$blRes{$k}}[11];
		#print $eval."\n";
		#sort by eval #changed from bestE -> bestScore
		#if ( ( ($emode && $bestE > $eval) || ($scomode && $bestScore< ($id * $AlLen)) ) 
		#			#&& ($eval <= $minBLE || $bitSc >= $minScore)
		#			&& ($quCovFrac == 0 || $AlLen > $DBlen{$Subject}*$quCovFrac) 
		#			&& (($fndCat || $noHardCatCheck) || exists $c2CAT{$Subject}) ) {
		#			#print "Y";
		
		#my $curScore = ${$blasts{$k}}[2] * ${$blasts{$k}}[3];
		#if ($bestScore < $curScore){$curScore = $bestScore;$bestk = $k;	}
		
		#	$bestAlLen=$AlLen;$bestE = $eval;#$bestQuery = $Query;
		
		#just sort by bitscore
		#print "@{$blasts{$k}}\n";
		#if ($bestBit < ${$blasts{$k}}[11]){
		#	$bestBit = ${$blasts{$k}}[11];  $bestk = $k;
		#}
		my $cID = ${$blasts{$k}}[2]; my $cLe = ${$blasts{$k}}[3]; my $cSc=${$blasts{$k}}[11];
		if (($bestID -5)< $cID){
			if ( ( $cID >= ($bestID *0.97) && $cID >= $bestIDever*0.9   && ( $cLe >= $bestLen * 1.15 ) )  ||  #length is just better (15%+)
					(   ($cID >= $bestID *1.03) && ( $cLe >= $bestLen * 0.9) ) ||#id is just better, while length is not too much off
					$cSc > $bestBit*0.8){   #convincing score
				$bestID = $cID;  $bestk = $k; $bestLen = $cLe; $bestBit = $cSc;
				if ($bestID > $bestIDever){$bestIDever=$bestID;}
			}
		}
	}
	if ($bestk eq ""){die "something went wrong with ABR blast:\n$k:$blasts{$k}\n";}
	return $blasts{$bestk};
}

sub help(){
print "Routine to interpret diamond output files to specific datbases (CAZy, KEGG, eggNOG)\n";
print "-i [diamond output]\n";
}





