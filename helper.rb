require 'confkit'
require 'yaml'

class PdflatexError < RuntimeError
end

helpers do
  def remove_wiki_block(page, tag)
    first_ind = page.index(tag)
    second_ind = page[first_ind+tag.size..page.size].index(tag)
    page[0...first_ind] + page[first_ind+second_ind+2*tag.size..page.size]
  end

  def gsub_markup(page, tag, tex_code)
    #page.scan(/#{tag}(?:(?!#{tag}).)*#{tag}/).each { |inside| page[inside] = inside.scan(/#{tag}(.*)#{tag}/).to_s }
    page.gsub("#{tag}", "")
  end 

  def to_italic(str)
    str.gsub!(/_([^_ ].*[^_ ])_/,'\textit{\1}')
  end

  def retrieve_page(page_id)
    conn_info = YAML.load_file(File.expand_path('~/.wikidata'))
    confl_cli = ConfKit::WikiClient.new(:url => conn_info[:server], :login => conn_info[:user], :password => conn_info[:password])
    page = confl_cli.getPage(page_id)
    page
  end

  def make_tex(tmpl, page)
    head = File.readlines("#{tmpl}.tex")
    body = page['content']
    body.gsub!(/\r/,'')

    body.gsub!(/^h[1-5]\. Литература.*/, '')
    body.gsub!(/^h2\. (.*)/, '\title{\1}')
    body.gsub!(/^h3\. (.*)/, '\section{\1}')
    body.gsub!(/^h4\. (.*)/, '\subsection{\1}')
    body.gsub!(/^h5\. (.*)/, '\subsubsection{\1}')
    body.gsub!("{latex}", "")
    body = remove_wiki_block(body, "{info}")
    body.gsub!(/ _([^_ ].*[^_ ])_ /,'\textit{\1}')  #to_italic
    body.gsub!(/\*([^\* ].*[^\* ])\*/,'\textbf{\1}')  #to_bold
    body.gsub!(/"([^"]*)"/m, '<<\1>>') #quotas
    body.gsub!(/ \[#(\S+)\]/, '~\cite{\1}') #reference to bibliography with leading space, replace it to '~'
    body.gsub!(/~\[#(\S+)\]/, '~\cite{\1}') #reference to bibliography
    body.gsub!(/\{anchor:(\S+)\}/, '\bibitem{\1}') 
    body.gsub!(/_/, '\_')
    body.gsub!(/\{code\}((?:(?!\{code\}).)*)\{code\}/m, '\begin{lstlisting}[frame=none]\1\end{lstlisting}')
    body.gsub!(/\{panel\}((?:(?!\{panel\}).)*)\{panel\}/m, '\begin{biblio}\1\end{biblio}')
    body.gsub!(/\{\{((?:(?!\{\{).)*)\}\}/m, '\texttt{\1}')  # monospaced font
    tail = "\\end{document}"
    head.to_s + body + tail
  end

  def tex_to_pdf(tex, tex_file)
    File.open(tex_file, 'w') do |f|
      f.puts tex
    end
    out = ""
    3.times{ out = out + `pdflatex -halt-on-error #{tex_file}` }
    raise PdflatexError, "PDF creation error! Not uploading renewed files." unless $?.exitstatus.eql? 0
    out
  end

  def upload_files(page_id)
    conn_info = YAML.load_file(File.expand_path('~/.wikidata'))
    confl_cli = ConfKit::WikiClient.new(:url => conn_info[:server], :login => conn_info[:user], :password => conn_info[:password])

    attach = {}
    attach[:pdf] = {"title"=>"#{page_id}.pdf", "fileName"=>"#{page_id}.pdf", "contentType"=>"application/pdf", "comment"=>"Uploaded by robot", "pageId"=>"#{page_id}"}
    attach[:tex] = {"title"=>"#{page_id}.tex", "fileName"=>"#{page_id}.tex", "contentType"=>"application/tex", "comment"=>"Uploaded by robot", "pageId"=>"#{page_id}"}

    %w{ pdf tex }.each do |file_type|
      att_data = ""   # data array does not work, init as string instead
      f = File.open("#{page_id}.#{file_type}", "rb")  # don't forget the 'b' for binary
      f.read.each_byte {|byte| att_data << byte }
      f.close
       
      confl_cli.addAttachment("#{page_id}", attach[file_type.to_sym], XMLRPC::Base64.new(att_data))
    end
    "Attachment #{page_id} uploaded successfully"
  end

  def create_pdf(tmpl, page_id)
    page = retrieve_page(page_id)
    tex = make_tex(tmpl, page)
    begin
      tex_out = tex_to_pdf(tex, "#{page_id}.tex")
      upload_out = upload_files(page_id)
    rescue PdflatexError
      tex_out = ""
      upload_out = "ERROR IN PDF CREATION. OUTPUT LOG FILE:" + File.readlines("#{page_id}.log").to_s
    end
    tex_out + upload_out
  end
end
