require 'thor'
require 'net/ftp'
require 'curb'

class Sra
  attr_reader :url, :reads, :topics, :ftp
  attr_accessor :lite

  PATH_BY_TYPE={"SRX"=>"ByExp","SRR"=>"ByRun", "SRS"=>"BySample","SRP"=>"ByStudy"}
  PATH_BY_NAME={"ByExp"=>"SRX","ByRun"=>"SRR","BySample"=>"SRS","ByStudy"=>"SRP"}
  PATH_SUB_SRA="sra"
  RESERVED_WORDS=%w{SRX ByExp SRR ByRun SRS BySample SRP ByStudy}

  def initialize
    @url = "ftp-trace.ncbi.nih.gov"
    @reads = "sra/sra-instant/reads"
    @ftp = nil
    @lite = true
  end

  def login
    @ftp=::Net::FTP.new(url)
    ftp.login
    ftp.chdir(reads)
    ftp
  end

  def list(search="")
    build_keywords_path(search).map do |path|
     #TODO:delete puts path
      ftp.list path
    end
  end
  
  def paths(search="")
    sra_list={}
    build_keywords_path(search).each do |path|
      sra_list[path]=[]
      ftp.list(path).each do |link|
        sra_list[path]<<link.split.last #if link=~/\.sra$/
      end
    end
    sra_list
  end
  
  def complete_path(*args)
    ["ftp://"+url,reads,args].join("/")
  end
  
  private
  def sra_sub_path
    (lite ? "lite" : "")+PATH_SUB_SRA
  end
  
  def build_keywords_path(search)
    valid_search_keywords(search).map do |keyword|
      build_keyword_path(keyword)
    end 
  end

  def build_keyword_path(word)
    #TODO: Refactor, is very very ugly
    #ByExp
    #SRR:000
    #SRR000123
    #ByExp:000
    #ByExp:000123  
    path=nil
    if word.empty?
      path=""
    elsif RESERVED_WORDS.include?(word)
      if word=~/^SR/
        path=PATH_BY_TYPE[word]+"/"+sra_sub_path+"/"+word
      else
        path=word+"/"+sra_sub_path+"/"+PATH_BY_NAME[word]
      end
      path=path
    else
      if complex_path?(word)
        path = build_complex_path(word)
      elsif word.include?(':') && (word.split(':').last.length==3 || word.split(':').last.length==6)        
        type = PATH_BY_TYPE[word[0..2]] 
        path = type +"/"+sra_sub_path+"/"+PATH_BY_NAME[type]+"/"+(word.length==9 ? word[0..5]+"/"+word : word)
      end
    end
    path
  end

  def complex_path?(word)
    word.include?(':') && (word.split(':').last.length==3 || word.split(':').last.length==6)
  end
  
  def build_complex_path(word)
    #TODO: Refactor, is very very ugly
    cword=word.split(':')
    cword_leaf = (cword.last.length == 6)
    cword_type = word_type(cword.first)
    build_keyword_path(cword.first)+"/"+cword_type+cword.last[0..2]+(cword_leaf ? "/"+cword_type+cword.last : '')
  end
  
  def word_type(word)
    #RESERVED_WORDS.include?(word) && (PATH_BY_NAME[word] || word)
    PATH_BY_NAME[word] || word 
  end
  
  def clean_keyword(kword)
    kword.gsub(/[0-9]*/,'')
  end

  #return the keywords valid for searching
  def valid_search_keywords(search="")
    if search.empty?
      [""]
    else
      search.split(",").select do |kword|
        fword=kword.split(':').first
        fword=~(/SR(X|R|S|P)[0-9]*/) || RESERVED_WORDS.include?(fword)
      end
    end
  end
end

class Sradl < Thor

  map "-L" => :list
  map "-D" => :download

  desc "list [SEARCH]", "list all available archives, limited by SEARCH"
  def list(search="")
    sra = Sra.new
    sra.login
    sra.list(search).each do |result|
      puts result
    end
  end
  
  desc "download [RUNs]", "list all available archives, limited by RUNs. It's a recursive procedure."
  def download(search="")
    sra = Sra.new
    sra.login
    urls=[]
    paths=sra.paths(search)
#TODO:delete    puts paths
    paths.each_pair do |path, sra_files|
      sra_files.each do |sra_file_name|
#TODO:delete        
puts sra_file_name
        if (sra_file_name=~/sra/)
          urls << sra.complete_path(path,sra_file_name)
        else
          (sra.ftp.list path+"/"+sra_file_name).each do |down|
            sra_files << sra_file_name + "/" + down.split.last
          end
        end
        #system "wget -O #{sra_file_name} \"#{sra.complete_path(path,sra_file_name)}\"&"
      end 
    end
    Curl::Multi.download(urls){|c,code,method| 
        filename = c.url.split(/\?/).first.split(/\//).last
        puts filename
      }
  end
end