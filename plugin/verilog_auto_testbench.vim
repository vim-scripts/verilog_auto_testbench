"=============================================================================
" FileName   :  verilog_auto_testbench.vim
" Author     :  wangjun
" Email      :  wangjun850725@gmail.com
" Description:  verilog automatic testbench.Base on hdl_plugin.vim by chengyong.
"               http://vim.wendal.net/scripts/script.php?script_id=3420
" Version    :  1.0
" LastChange :  2013-05-23 15:02:35
" ChangeLog  :  Removed some unnecessary functions, because it can be easily done using snipmate
"               Fixed module that there is comment(eg.'^\s\+\/\/.*') can not be instantiated 
"               Fixed module that there is comment(eg.'^\/\/') can not be instantiated 
"               Fixed module that there is comment(eg.'\s*\/\/.*') can not be instantiated 
"               Fixed module that there is parameter declaration can not be instantiated 
"               Remove menu
" Useage    : ,tb           generate testbench
"=============================================================================
if exists('b:verilog_auto_testbench') || &cp || version < 700
    finish
endif
let b:verilog_auto_testbench = 1

nmap    ,tb     :call HDL_Tb_Build("verilog")<cr>

if !exists("g:HDL_Clock_Period")
    let g:HDL_Clock_Period = "CLKPERIOD"
endif

"------------------------------------------------------------------------
"Function    : HDL_Entity_Information() 
"Decription  : get position and port map of the entity 
"------------------------------------------------------------------------
function HDL_Entity_Information()
    " 保存初始位置，entity读取完成跳转回来
    exe "ks"
    if HDL_Check_Filetype() == 2
        " 找到文件module
        let module_line = search('\(\/\/.*\)\@<!\<module\>','w')
        if module_line == 0
            echo "Can't Find The Module."
            return 0
        endif
        " 得到module的名字
        let line = getline(module_line)
        let s:ent_name = substitute(line,'\%(\/\/.*\)\@<!\<module\>\s*\(\<[a-zA-Z0-9_]*\>\).*$',"\\1","")
        " 寻找下一个出现的括号来找到端口列表的首行和尾行
        if search(");",'W')
            let last_line   = line('.')
            exe "normal %"
            let first_line  = line('.')
        elseif
            return 0
        endif
        " 端口input，output等信息存于list--port_information中
        let port_information = []
        for line in getline(last_line,line('$'))
            if line =~ '^\s\+\/\/.*'          "by wj
                continue
            endif
            if line =~ '\%(\/\/.*\)\@<!\<\%[in]\%[out]\%[put]\>'            "match input or output 
                let line = substitute(line,' ^\s*\%(\/\/.*\)\@<!\(\<\%[in]\%[out]\%[put]\>.*\)\s*;\s*$',"\\1","")
                call add(port_information,line)
            endif
        endfor
        " 所有端口存于ports中
        let ports = ''
        for line in getline(first_line,last_line)
            if line !~ '^\s\+\/\/.*'          "by wj
                if line !~ '^\/\/'
                    let line = substitute(line,'^.*(\s*',"","")
                    let line = substitute(line,'\s*\/\/.*',"","")               "delete comment part about port comment 
                    let line = substitute(line,'\s*)\_s*;.*$',"","")
                    let ports = ports.line
                endif
            endif
        endfor

        " 去掉空格
        let ports = substitute(ports,'\s\+',"","g")
        " 得到ports中每个逗号的位置，并加入list--comma_pos
        let comma_pos = [-1]
        let j = 1
        while 1
            let last_comma = stridx(ports,",",comma_pos[j-1]+1)
            call add(comma_pos,last_comma)
            if comma_pos[j] == -1
                break
            endif
            let j = j + 1
        endwhile  
        " 将各个端口信息转成vhdl的方式存于list中
        let k = 0
        let s:port = []
        let s:direction = []
        let s:type = []
        let s:port_cout = 0
        let s:parameter_cout = 0 
        " 端口名字port加入s:port中
        while k < j 
            if k == j - 1
                let port = strpart(ports,comma_pos[k]+1) 
            else
                let port = strpart(ports,comma_pos[k]+1,comma_pos[k+1]-comma_pos[k]-1)
            endif
            call add(s:port,port)
            " 在port_information中寻找port，如果找到，就将相应信息加入list
            let num = match(port_information,port)
            if num == -1
                echohl Keyword
                echo "port ".port."is not define"
                return 0
            elseif port_information[num] =~ '\<input\>'
                call add(s:direction,"in")
            elseif port_information[num] =~ '\<output\>'
                call add(s:direction,"out")
            elseif port_information[num] =~ '\<inout\>'
                call add(s:direction,"inout")
            endif
            " 有长度信息的[x:y] 则转化成std_logic_vector(x downto y)存入s:type，如果没有则为std_logic
            let len_start = stridx(port_information[num],"[")
            if len_start != -1 
                let len_end = stridx(port_information[num],"]")
                let len = strpart(port_information[num],len_start,len_end-len_start+1)
                let type = HDL_Change2Vhdl(len)
                call add(s:type,type)
            else 
                call add(s:type,"std_logic")
            endif

            let s:port_cout = s:port_cout + 1
            let k = k + 1
        endwhile
        " 暂时不支持generic，设置generic_start_line = 0
        let s:generic_start_line = 0
    else 
        return 0
    endif
    " 跳转回刚刚标记的地方
    "echo s:port
    "echo s:direction
    "echo s:type
    """""""""exe "'s"
    return 1
endfunction


"------------------------------------------------------------------------
"Function    : HDL_Check_Filetype()
"Decription  : Check file type 
"               if vhdl return 1
"               if verilog return 2
"               if vim return 3
"               others return 0
"------------------------------------------------------------------------
function HDL_Check_Filetype()
    if expand("%:e") == "v" 
        return 2
    elseif expand("%:e") == "vim" 
        return 3
    else 
        return 0
    endif
endfunction

"-----------------------------------------------------------------------
"Function    : HDL_Change2vlog(port_tp) 
"Decription  : port_tp is std_logic_vector(x downto y)
"               return a string as [x:y] 
"------------------------------------------------------------------------
function HDL_Change2vlog(port_tp)
    if a:port_tp =~ '\<std_logic_vector\>'
        let mid = substitute(a:port_tp,'\<std_logic_vector\>\s*(',"","")
        if a:port_tp =~ '\<downto\>'
            let high_tp = substitute(mid,'\s*\<downto\>.*',"","")
            let low_tp = substitute(mid,'.*\<downto\>\s*',"","")
            let low_tp = substitute(low_tp,'\s*).*',"","")
        elseif a:port_tp =~ '\<to\>'
            let high_tp = substitute(mid,'\s*\<to\>.*',"","")
            let low_tp = substitute(mid,'.*\<to\>\s*',"","")
            let low_tp = substitute(low_tp,'\s*).*',"","")
        else 
            return "Wrong"
        endif
        let vlog_tp = "[".high_tp.":".low_tp."]"
    else 
        return "Wrong"
    endif
    return vlog_tp
endfunction

"-------------------------------------------------------------------------------
" Function		: HDL_Change2Vhdl(port_tp)	
" Description	: port_tp is [x:y]	
"                   return a string as std_logic_vector(x downto y)
"-------------------------------------------------------------------------------
function HDL_Change2Vhdl(port_tp)
    let port_tp = substitute(a:port_tp,'\s*',"","g")
    let colon = stridx(port_tp,":")
    let high_tp = strpart(port_tp,1,colon-1)
    let low_tp = strpart(port_tp,colon+1,strlen(port_tp)-colon-2)
"    echo "high_tp= ".high_tp
"    echo "low_tp= ".low_tp
    if high_tp > low_tp
        let vhdl_tp = "std_logic_vector(".high_tp." downto ".low_tp.")"
    else 
        let vhdl_tp = "std_logic_vector(".high_tp." to ".low_tp.")"
    endif
    return vhdl_tp
endfunction


"------------------------------------------------------------------------
"Function    : HDL_Component_Part(lang)
"Decription  : build component part
"------------------------------------------------------------------------
function HDL_Component_Part(lang)
    if a:lang == "verilog"
        return ''
    else 
        return ''
    endif
endfunction

"------------------------------------------------------------------------
"Function    : HDL_Instant_Part(lang)
"Decription  : build instant_part 
"------------------------------------------------------------------------
function HDL_Instant_Part(lang)
    if a:lang == "verilog"
        let instant_part = s:ent_name."\t"
        if s:generic_start_line != 0
            let i = 0
            let instant_part = instant_part."#(\n"
            let parameter = ""
            while i < s:generic_count
                if s:generic_value[i] != ""
                    let parameter = parameter."parameter\t".s:generic_port[i]." = ".s:generic_value[i].";\n"
                else 
                    let parameter = parameter."parameter\t".s:generic_port[i]." = //Add value;\n"
                endif
                if strwidth(s:generic_port[i])<3
                    let instant_part = instant_part."\t.".s:generic_port[i]."\t\t\t\t(".s:generic_port[i].")"
                elseif strwidth(s:generic_port[i])<7 && strwidth(s:generic_port[i])>=3
                    let instant_part = instant_part."\t.".s:generic_port[i]."\t\t\t(".s:generic_port[i].")"
                elseif strwidth(s:generic_port[i])<11 && strwidth(s:generic_port[i])>=7
                    let instant_part = instant_part."\t.".s:generic_port[i]."\t\t(".s:generic_port[i].")"
                elseif strwidth(s:generic_port[i])<15 && strwidth(s:generic_port[i])>=11
                    let instant_part = instant_part."\t.".s:generic_port[i]."\t(".s:generic_port[i].")"
                else
                    let instant_part = instant_part."\t.".s:generic_port[i]."(".s:generic_port[i].")"
                endif
                if i != s:generic_count - 1
                    let instant_part = instant_part.",\n"
                else 
                    let instant_part = instant_part."\n)\n"
                endif
                let i = i + 1
            endwhile
            let instant_part = parameter."\n".instant_part
        endif
        let instant_part = instant_part.s:ent_name."Ex01\n(\n"
        let i = 0
        while i < s:port_cout
            if strwidth(s:port[i])<3
                let instant_part = instant_part."\t.".s:port[i]."\t\t\t\t(".s:port[i]
            elseif strwidth(s:port[i])<7 && strwidth(s:port[i])>=3
                let instant_part = instant_part."\t.".s:port[i]."\t\t\t(".s:port[i]
            elseif strwidth(s:port[i])>=7 && strwidth(s:port[i])<11
                let instant_part = instant_part."\t.".s:port[i]."\t\t(".s:port[i]
            elseif strwidth(s:port[i])>=11 && strwidth(s:port[i]) <15
                let instant_part = instant_part."\t.".s:port[i]."\t(".s:port[i]
            else
                let instant_part = instant_part."\t.".s:port[i]."(".s:port[i]
            endif
            if i != s:port_cout - 1
                let instant_part = instant_part."),\n"
            else 
                let instant_part = instant_part.")\n);\n\n"
            endif
            let i = i + 1
        endwhile
    elseif
        return ''
    endif
    return instant_part
endfunction
"------------------------------------------------------------------------
"Function    : HDL_Para_Part(lang) 
"Decription  : inport part 
"------------------------------------------------------------------------
function HDL_Para_Part(lang)
    if a:lang == "verilog"
    endif
endfunction
"------------------------------------------------------------------------
"Function    : HDL_Inport_Part(lang) 
"Decription  : inport part 
"------------------------------------------------------------------------
function HDL_Inport_Part(lang)
    if a:lang == "verilog"
        let inport_part = "// Inputs\n"
        let i = 0
        while i < s:port_cout 
            if s:direction[i] == "in"
                let inport_part = inport_part."reg\t\t\t\t".s:port[i].";\n"
            endif
            let i = i + 1
        endwhile
        if inport_part == "// Inputs\n"
            let inport_part = ''
        else 
            let inport_part = inport_part."\n"
        endif
    else 
        return ''
    endif
    return inport_part
endfunction

"------------------------------------------------------------------------
"Function    : HDL_Outport_Part(lang) 
"Decription  : outport part 
"------------------------------------------------------------------------
function HDL_Outport_Part(lang)
    if a:lang == "verilog"
        let outport_part = "// Outputs\n"
        let i = 0
        while i < s:port_cout 
            if s:direction[i] == "out"
                let outport_part = outport_part."wire\t\t\t".s:port[i].";\n"
            endif
            let i = i + 1
        endwhile
        if outport_part == "// Outputs\n"
            let outport_part = ''
        else 
            let outport_part = outport_part."\n"
        endif
    else 
        return ''
    endif
    return outport_part
endfunction
"
"------------------------------------------------------------------------
"Function    : HDL_Inoutport_Part(lang) 
"Decription  : inoutport part 
"------------------------------------------------------------------------
function HDL_Inoutport_Part(lang)
    if a:lang == "verilog"
        let inoutport_part = "// Inout\n"
        let i = 0
        while i < s:port_cout 
            if s:direction[i] == "inout"
                    let inoutport_part = inoutport_part."wire\t\t\t".s:port[i].";\n"
            endif
            let i = i + 1
        endwhile
        if inoutport_part == "// Inout\n"
            let inoutport_part = ''
        else 
            let inoutport_part = inoutport_part."\n"
        endif
    else 
        return ''
    endif
    return inoutport_part
endfunction



"-----------------------------------------------------------------------
"Function    : HDL_Tb_Build() 
"Decription  :  
"------------------------------------------------------------------------
function HDL_Tb_Build(type)
    if a:type == ''
        echo "Do not set \"type\""
        return
    endif
"  Check the file type
    if !HDL_Check_Filetype()
        echohl ErrorMsg
        echo    "This file type is not supported!"
        echohl None
        return
    endif
"    get information of the entity
    if !HDL_Entity_Information() 
        echo "Can't Get the information"
        return
    endif
    if !exists('clk')
        let clk = "clk"
    endif
    if !exists('rst')
        let rst = "rst"
    endif
"    file name and entity name 
    let tb_ent_name = s:ent_name."Tb"      "by wj  2013-5-23 12:39:13
    if a:type == "verilog"
        let tb_file_name = s:ent_name."Tb".".v"
        let entity_part = ''
        let architecture_part ="`timescale  1ns/1ps\n`define     DELAY   1\n\n"."module ".tb_ent_name."() ;\n"
        let constant_part = ''
        let half_clk = g:HDL_Clock_Period
        let clock_part = "// Clock generate \nalways \n\t# ".half_clk."/2"."\t".clk." <= ~".clk.";\n\n"
        let simulus_part = "initial \nbegin\n"
        let i = 0
        while i < s:port_cout
            if s:direction[i] == "in"
                let simulus_part = simulus_part."\t".s:port[i]." = 0;\n"
            endif
            let i = i + 1
        endwhile

        "let simulus_part = simulus_part."end\n\nendmodule\n"
    endif
     "    component part
    let component_part = HDL_Component_Part(a:type)
    let parameter_part = HDL_Para_Part(a:type)
    let inport_part = HDL_Inport_Part(a:type)
    let outport_part = HDL_Outport_Part(a:type)
    let inoutport_part = HDL_Inoutport_Part(a:type)
    let instant_part = HDL_Instant_Part(a:type)
    let all_part = entity_part.architecture_part.component_part.inport_part.outport_part
                \.inoutport_part.constant_part.clock_part.simulus_part."end\n\n".instant_part."endmodule\n"
"    检测文件是否已经存在 
    if filewritable(tb_file_name) 
        let choice = confirm("The testbench file has been exist.\nSelect \"Open\" to open existed file.".
                    \"\nSelect \"Change\" to replace it.\nSelect \"Cancel\" to Cancel this operation.",
                    \"&Open\nCh&ange\n&Cancel")
        if choice == 0
            echo "\"Create a Testbench file\" be Canceled!"
            return
        elseif choice == 1
            exe "bel sp ".tb_file_name
            "exe "tabe".tb_file_name
            return
        elseif choice == 2
            if delete(tb_file_name) 
                echohl ErrorMsg
                echo    "The testbench file already exists.But now can't Delete it!"
                echohl None
                return
            else 
                echo "The testbench file already exists.Delete it and recreat a new one!"
            endif
        else 
            echo "\"Create a Testbench file\" be Canceled!"
            return
        endif
    endif
    exe "bel sp ".tb_file_name
    silent put! =all_part
    if search('\<rst\>.*=') != 0
        exe "normal f0r1"
    endif
    exe "up"
    call search("Add stimulus here")
endfunction

