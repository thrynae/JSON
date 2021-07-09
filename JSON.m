function [object,ME]=JSON(str,varargin)
% This interprets char array as JSON and returns an object the same size and shape as the builtin.
%
% This was implemented using
% https://www.ecma-international.org/wp-content/uploads/ECMA-404_2nd_edition_december_2017.pdf
% The failing and passing cases were validated using the test cases from a JSON test suite on
% GitHub (http://github.com/nst/JSONTestSuite), containing over 300 cases of possibly ambiguous
% syntax. Because the standard is not explicit for every situation, there are also test cases left
% to the implementation.
%
% Implementation details for compatibility with the jsondecode Matlab function:
% - If possible an array of arrays is treated as a row-major matrix.
%   * all data types should match
%   * all elements must be vectors of the same size
% - The null literal is an empty double, unless it is an element of an array, in which case it is
%   parsed as a NaN.
% - The name of an object is converted to a valid field name with a function similar to genvarname
%   or matlab.lang.makeValidName. This means characters after some whitespace characters are
%   converted to uppercase, all whitespace is removed, invalid characters are replaced by an
%   underscore, and an x is used as a prefix if the resulting name is empty or starts with a number
%   or underscore. In case of duplicate object names, an underscore and a counter is added. A
%   char(0) will cause the name to be cropped.
% - An empty array ('[]') is encoded as an empty double (val=[]).
% - An empty array array of arrays ('[[]]') is encoded as an empty cell (val={[]}).
%
%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%
%|                                                                         |%
%|  Version: 1.0.0                                                         |%
%|  Date:    2021-09-07                                                    |%
%|  Author:  H.J. Wisselink                                                |%
%|  Licence: CC by-nc-sa 4.0 ( creativecommons.org/licenses/by-nc-sa/4.0 ) |%
%|  Email = 'h_j_wisselink*alumnus_utwente_nl';                            |%
%|  Real_email = regexprep(Email,{'*','_'},{'@','.'})                      |%
%|                                                                         |%
%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%
%
% Tested on several versions of Matlab (ML 6.5 and onward) and Octave (4.4.1 and onward), and on
% multiple operating systems (Windows/Ubuntu/MacOS). For the full test matrix, see the HTML doc.
% Compatibility considerations:
% - The recursion depth is limited to 100. This will affect all combinations of nesting of arrays
%   and objects. Without this, the recursion limit may be reached, causing Matlab/Octave to crash.
%   Matlab/Octave should prevent this on their own, but this is in place in case that protection
%   fails. The value can be set to inf to effectively remove the limit and only rely on the builtin
%   safeguards.

opts=struct;
opts.EnforceValidNumber=true;
opts.ThrowErrorForInvalid=nargout<2;
opts.MaxRecursionDepth=101-numel(dbstack);
opts=parse_NameValue(opts,varargin{:});
w=struct;w.w=warning('off','REGEXP:multibyteCharacters');[w.msg,w.ID]=lastwarn;
try ME=[];
    notation=StrToNotation(str,opts);
    object=ParseValue(notation);
catch ME;if isempty(ME),ME=lasterror;end %#ok<LERR>
end
warning(w.w);lastwarn(w.msg,w.ID);%Reset warning state.
if ~isempty(ME)%An error has occurred.
    if opts.ThrowErrorForInvalid,rethrow(ME)
    else,                        object=[]; end
end
end
function notation=StrToNotation(str,opts)
%Treat the notation as a class, with the following properties (i.e. struct fields):
%  str : the actual notation input
%  s_tokens : a copy of str with only the structural tokens
%  braces : an array encoding the pairs of braces (0 for non-brace characters)
%  depth : approximate current recursion depth
%  opts : a struct with options
%
% Any whitespace allowed by the specification (i.e. [9 10 13 32]) will be removed outside of the
% strings to facilitate easier parsing.

if isa(str,'string'),str=cellstr(str);end
if iscellstr(str),str=sprintf('%s\n',str{:});end
if ~isa(str,'char') || numel(str)~=length(str)
    throw_error('The input should be a char vector or a string/cellstr.','Input')
end
str=reshape(str,1,[]);%Ensure str is a row vector.

persistent args ws legacy
if isempty(args)
    ws=[9 10 13 32];%this is not equal to \s
    args={['[' char(ws) ']*([\[{\]}:,])[' char(ws) ']*'],'$1','tokenize'};
    
    
    %The 'tokenize' option became the default in R14 (v7).
    v=version;v(min(find(v=='.')):end)='';pre_v7=str2double(v)<7; %#ok<MXFND>
    isOctave=exist('OCTAVE_VERSION','builtin')~=0;
    if ~pre_v7 && ~isOctave
        args(end)=[];
    end
    
    %Check if the regex crops special characters like char(0).
    legacy= 3==numel(regexprep(['123' char([0 10])],args{:})) ;
end

%This is true for the text including the double quotes.
txt=FindLiteralTextPositions(str);

%Remove whitespace that will not be parsed.
s_tokens=str;s_tokens(txt)='_';
if ~legacy
    s_tokens=regexprep(s_tokens,args{:});
else
    %Since the regex crops characters like char(0), we need to apply the regex to a surrogate.
    tmp=s_tokens;tmp(:)='n';                             %Mark all non-relevant.
    tmp(ismember(double(s_tokens),ws))='w';              %Mark all whitespace
    tmp(ismember(double(s_tokens),double('[{}]:,')))='t';%Mark all tokens
    L=zeros(1,1+numel(tmp));%Extend size by 1 to make cumsum work.
    [s,e]=regexp(tmp,'w+t');
    if ~isempty(s),L(s  )=1;L(e  )=-1;end
    [s,e]=regexp(tmp,'tw+');
    if ~isempty(s),L(s+1)=1;L(e+1)=-1;end
    L=logical(cumsum(L));L(end)=[];
    s_tokens(L)='';
end
while numel(s_tokens)>0 && any(s_tokens(end)==ws),s_tokens(end)='';end%Deal with lone values.
while numel(s_tokens)>0 && any(s_tokens(1)==ws),s_tokens(1)='';end%Deal with lone values.

%Apply whitespace removal to str as well.
str2=s_tokens;str2(s_tokens=='_')=str(txt);str=str2;

%Leave only structural tokens.
s_tokens(~ismember(double(s_tokens),double('[{}]:,')))='_';

[braces,ArrayOfArrays]=PairBraces(s_tokens);

notation.str=str;
notation.s_tokens=s_tokens;
notation.braces=braces;
notation.ArrayOfArrays=ArrayOfArrays;
notation.opts=opts;
notation.depth=0;
end
function txt=FindLiteralTextPositions(str)
%Characters after an odd number and before an even number double quote are part of a literal text.
%Since this is only true if there are no escaped double quotes, we need to mask those.
str=strrep(str,'\"','__');%Mask escaped double quotes.
L=str=='"';%Find all double quotes.
x=cumsum(L);%Count prior double quotes.
txt=L | mod(x,2)~=0;%Find the location of literal text.
end
function [braces,ArrayOfArrays]=PairBraces(s_tokens)
%Pair the braces and brackets and determine which positions are part of an array of arrays.

braces=zeros(size(s_tokens));
L=s_tokens=='{';
braces(L)=1:sum(L);
try
    L2=find(L);
    for ind=find(s_tokens=='}')
        %Equivalent to match=find(L(1:ind),1,'last').
        ind2=find(L2<ind);ind2=ind2(end);match=L2(ind2);L2(ind2)=[];
        braces(ind)=-braces(match);
        L(match)=false;
    end
    if any(L),error('trigger'),end
catch
    msg='Unmatched braces found.';
    id='PairBraces';
    throw_error(msg,id)
end
L=s_tokens=='[';
braces(L)=max(braces)+(1:sum(L));
try
    L2=find(L);
    for ind=find(s_tokens==']')
        %Equivalent to match=find(L(1:ind),1,'last').
        ind2=find(L2<ind);ind2=ind2(end);match=L2(ind2);L2(ind2)=[];
        braces(ind)=-braces(match);
        L(match)=false;
    end
    if any(L),error('trigger'),end
catch
    msg='Unmatched braces found.';
    id='PairBraces';
    throw_error(msg,id)
end

ArrayOfArrays=false(1,numel(s_tokens));
%Keep only the brackets and create a reduced form of the indices of the braces.
x=s_tokens(ismember(double(s_tokens),double('[{}]')));
br=braces(braces~=0);
%Find the starting positions of the array of arrays (i.e. the inner-most '[[').
[s,e]=regexp(x,'(\[)+\[');e=e-1;
for n=1:numel(s)
    %Mark each array of arrays with a counter.
    ArrayOfArrays(braces==br(e(n)))=true;
end
end
function notation=index(notation,indices)
%If the second input is a scalar, this is interpreted as indices:end.
if numel(indices)==1,indices(2)=numel(notation.str);end
indices=indices(1):indices(2);
notation.str=notation.str(indices);
notation.s_tokens=notation.s_tokens(indices);
notation.braces=notation.braces(indices);
notation.ArrayOfArrays=notation.ArrayOfArrays(indices);
end
function throw_error(msg,id)
error(['HJW:JSON:' id],msg)
end
function val=ParseValue(notation)
persistent number
if isempty(number)
    number=num2cell('-0123456789');
end
if numel(notation.str)==0,notation.str=' ';end%This will trigger an error later.
%Limit recursion depth to avoid crashes.
notation.depth=notation.depth+1;
if notation.depth>notation.opts.MaxRecursionDepth
    throw_error('Recursion limit reached, exiting to avoid crashes.','Recursion')
end

switch notation.str(1)
    case '{'
        val=ParseObject(notation);
    case '['
        val=ParseArray(notation);
    case number
        val=ParseNumber(notation.str,notation.opts.EnforceValidNumber);
    case '"'
        val=ParseString(notation.str);
        %Avoid 1x0 chars.
        if numel(val)==0,val='';end
    case 't'
        if ~strcmp(notation.str,'true')
            msg='Unexpected literal, expected ''true''.';
            id='Literal';
            throw_error(msg,id)
        end
        val=true;
    case 'f'
        if ~strcmp(notation.str,'false')
            msg='Unexpected literal, expected ''false''.';
            id='Literal';
            throw_error(msg,id)
        end
        val=false;
    case 'n'
        if ~strcmp(notation.str,'null')
            msg='Unexpected literal, expected ''null''.';
            id='Literal';
            throw_error(msg,id)
        end
        val=[];
    otherwise
        msg='Unexpected character, expected a brace, bracket, number, string, or literal.';
        id='Literal';
        throw_error(msg,id)
end
end
function val=ParseObject(notation)
ind=find(notation.braces==-notation.braces(1));%Find the matching closing brace.
if numel(ind)~=1 || ind~=numel(notation.str) || ~strcmp(notation.str([1 end]),'{}')
    msg='Unexpected end of object.';
    id='Object';
    throw_error(msg,id)
end

val=struct;
if ind==2,return,end%Empty object: '{}'.

%Select the part of the notation between the braces.
to_parse=index(notation,[2 numel(notation.str)-1]);

%Split over the commas that are not inside braces.
c_ind=find(cumsum(to_parse.braces)==0 & to_parse.s_tokens==',');
c_ind=[0 c_ind numel(to_parse.str)+1];
c_ind=[c_ind(1:(end-1))+1;c_ind(2:end)-1];

%Split each pair in the string part and a value.
brace_content=cell(size(c_ind));
for n=1:size(c_ind,2)
    pair=index(to_parse,c_ind(:,n));
    L=pair.s_tokens==':';
    if ~any(L),throw_error('No colon found in object definition.','Object'),end
    ind=find(L);ind=ind(1);
    try
        brace_content{1,n}=ParseString(pair.str(1:(ind-1)));
    catch
        throw_error('Invalid key in object definition.','Object')
    end
    try
        brace_content{2,n}=ParseValue(index(pair,ind+1));
    catch
        throw_error('Invalid value in object definition.','Object')
    end
    if isa(brace_content{2,n},'cell')
        %Wrap in a scalar cell to avoid creating a struct array later.
        brace_content{2,n}=brace_content(2,n);
    end
end

%Determine the fieldnames.
persistent RE dyn_expr
if isempty(RE)
    ws=char([9 10 11 12 13 32]);
    RE=['[' ws ']+([^' ws '])'];
    
    %Dynamically check if the dynamic expression replacement is available. This is possible since
    %R2006a (v7.2), and has not been implemented yet in Octave 6.2.0.
    dyn_expr=strcmp('fooBar',regexprep('foo bar',RE,'${upper($1)}'));
end
for n=1:size(brace_content,2)
    fn=brace_content{1,n};
    if dyn_expr
        fn=regexprep(fn,RE,'${upper($1)}');%Convert characters after whitespace to upper case.
    else
        [s,e]=regexp(fn,RE);
        if ~isempty(s)
            fn(e)=upper(fn(e));
            L=zeros(size(fn));L(s)=1;L(e)=-1;L=logical(cumsum(L));
            fn(L)='';
        end
    end
    fn=regexprep(fn,'\s','');%Remove all remaining whitespace.
    x=find(double(fn)==0);if ~isempty(x),fn(x(1):end)='';end%Gobble null characters.
    fn=regexprep(fn,'[^0-9a-zA-Z_]','_');%Replace remaining invalid characters.
    if isempty(fn)||any(fn(1)=='_0123456789')
        fn=['x' fn]; %#ok<AGROW>
    end
    fn_=fn;counter=0;
    while ismember(brace_content(1,1:(n-1)),fn)
        counter=counter+1;fn=sprintf('%s_%d',fn_,counter);
    end
    brace_content{1,n}=fn;
end

%Store to struct
val=struct(brace_content{:});
end
function str=ParseString(str)
persistent dict_ dict_2 symbol_length
if isempty(dict_)
    symbol_length=zeros(1,double('u'));symbol_length(double('"\/bfnrtu'))=[ones(1,8) 5]+1;
    dict_={...
        '"','"';...
        '\','\';...
        '/','/';...
        'b',char(8);...
        'f',char(12);...
        'n',char(10);...
        'r',char(13);...
        't',char(9)}; %#ok<CHARTEN>
    dict_2=double([cell2mat(dict_(:,1));'u']);
    for n=1:size(dict_,1),dict_{n,1}=['\' dict_{n,1}];end
end
if ~strcmp(str([1 end]),'""')
    msg='Unexpected end of string.';
    id='StringDelim';
    throw_error(msg,id)
end
if any(double(str)<32)
    msg='Unescaped control character in string.';
    id='StringControlChar';
    throw_error(msg,id)
end
str=str(2:(end-1));%Remove outer double quotes.
ind=regexp(str,'\\.');
if any(ind)
    %Create a unique list of all replacements. To prevent double replacement, split the str in a
    %cell and replace each element separately.
    
    %Check if there are only valid escaped characters.
    if ~all(ismember(double(str(ind+1)),dict_2))
        msg='Unexpected escaped character.';
        id='StringEscape';
        throw_error(msg,id)
    end
    
    %Find the true indices (this will properly deal with "\\\u000D").
    ind=regexp(str,'\\["\\/bfnrtu]');
    
    %Find all unicode replacements.
    ind2=strfind(str,'\u');
    if ~isempty(ind2)
        HasUnicode=true;
        try
            ind2=bsxfun_plus(ind2.',0:5);
            U=cellstr(unique(str(ind2),'rows'));
            for n=1:numel(U)
                U{n,2}=unicode_to_char(hex2dec(U{n,1}(3:end)));
            end
        catch
            msg='Unexpected escaped character.';
            id='StringEscape';
            throw_error(msg,id)
        end
    else
        HasUnicode=false;
        U=cell(0,2);
    end
    dict=[U;dict_];
    
    %Encode the length of each segment.
    len=symbol_length(str(ind+1));
    len=[0 len;diff([0,ind,1+numel(str)])-[1 len]];
    str_c=mat2cell(str,1,len(:));
    str_c=reshape(str_c,2,[]);
    
    %Check for \ in normal text, this is probably already caught.
    if any([str_c{2,:}]=='\')
        msg='Unexpected escaped character.';
        id='StringEscape';
        throw_error(msg,id)
    end
    
    %Keep track of processed elements so we don't do unnecessary work.
    done=true(size(str_c));
    done(1,:)=false;
    done(cellfun('prodofsize',str_c)==0)=true;
    for n=1:size(dict,1)
        L=~done & ismember(str_c,dict{n,1});
        str_c(L)=dict(n,2);
        done(L)=true;
        if all(done),break,end
    end
    if any(~done)
        msg='Unexpected escaped character.';
        id='StringEscape';
        throw_error(msg,id)
    end
    str=horzcat(str_c{:});
    if HasUnicode && CharIsUTF8
        %Fix the mis-encoding for surrogate pairs in UTF-16. This is only relevant on runtimes
        %where char is encoded as UTF-8. Currently, that means this only applies to Octave.
        [str,ignore_flag]=UTF8_to_unicode(str); %#ok<ASGLU>
        str=unicode_to_char(UTF16_to_unicode(str));
    end
end
end
function num=ParseNumber(str,EnforceValidNumber)
if ~EnforceValidNumber
    isValidJSON=true;
else
    %The complete regexp below doesn't work for some reason, so do it in two passes.
    %
    %       ['-?((0)|([1-9]+\d*))(\.\d+)?([eE]' '[\+-]' '?[0-9]+)?']
    expr{1}=['-?((0)|([1-9]+\d*))(\.\d+)?([eE]'  '\+'   '?[0-9]+)?'];
    expr{2}=['-?((0)|([1-9]+\d*))(\.\d+)?([eE]'    '-'  '?[0-9]+)?'];
    if true
        [s,e]=regexp(str,expr{1},'once');
        isValidJSON=~isempty(s) && s==1 && e==numel(str);
    end
    if ~isValidJSON
        [s,e]=regexp(str,expr{2},'once');
        isValidJSON=~isempty(s) && s==1 && e==numel(str);
    end
end
if ~isValidJSON
    msg='Invalid number format.';
    id='Number';
    throw_error(msg,id)
end
num=str2double(str);
end
function val=ParseArray(notation)
ind=find(notation.braces==-notation.braces(1));%Find the matching closing bracket.
if numel(ind)~=1 || ind~=numel(notation.str) || ~strcmp(notation.str([1 end]),'[]')
    msg='Unexpected end of array.';
    id='Array';
    throw_error(msg,id)
end

if strcmp(notation.str,'[]')
    %Empty array: '[]'.
    val=[];return
end
if strcmp(notation.str,'[[]]')
    %Empty array of arrays: '{[]}'.
    val={[]};return
end

%Avoid indexing (to select the part of the notation between the brackets).
br=notation.braces;br(1)=0;

%Split over the commas that are not inside brackets.
c_ind=find(cumsum(br)==0 & notation.s_tokens==',');
c_ind=[1 c_ind numel(notation.str)];
c_ind=[c_ind(1:(end-1))+1;c_ind(2:end)-1];
if any(diff(c_ind,1,1)<0)
    msg='Empty array element.';
    id='Array';
    throw_error(msg,id)
end
val=cell(size(c_ind,2),1);
for n=1:size(c_ind,2)
    val{n}=ParseValue(index(notation,c_ind(:,n)));
end

%An array of arrays should be treated as a row-major matrix.
%These are the requirements to parse to a matrix:
% - all data types should match
% - all elements must be vectors of the same size
%   (null being NaN instead of [] in the case of a numeric matrix)
if notation.ArrayOfArrays(1)
    try
        tmp=val;
        tmp(cellfun('isempty',tmp))={NaN};
        val=horzcat(tmp{:}).';
        return
    catch
        %Revert to cell vector.
    end
end
if ismember(class(val{n}),{'double','logical','struct'})
    tmp=val;
    if all(cellfun('isclass',val,'double'))
        tmp(cellfun('isempty',tmp))={NaN};
        if numel(unique(cellfun('prodofsize',tmp)))==1
            val=horzcat(tmp{:}).';
            return
        end
    elseif all(cellfun('isclass',val,'logical'))
        if numel(unique(cellfun('prodofsize',val)))==1
            val=horzcat(val{:}).';
            return
        end
    elseif all(cellfun('isclass',val,'struct'))
        %This will fail for dissimilar structs.
        try val=vertcat(val{:});catch,end
    else
        %Leave as cell vector.
    end
end
end
function out=bsxfun_plus(in1,in2)
%Implicit expansion for plus(), but without any input validation.
try
    out=in1+in2;
catch
    try
        out=bsxfun(@plus,in1,in2);
    catch
        sz1=size(in1);                    sz2=size(in2);
        in1=repmat(in1,max(1,sz2./sz1));  in2=repmat(in2,max(1,sz1./sz2));
        out=in1+in2;
    end
end
end
function c=char2cellstr(str,LineEnding)
%Split char or uint32 vector to cell (1 cell element per line). Default splits are for CRLF/CR/LF.
%The input data type is preserved.
%
%Since the largest valid Unicode codepoint is 0x10FFFF (i.e. 21 bits), all values will fit in an
%int32 as well. This is used internally to deal with different newline conventions.
%
%The second input is a cellstr containing patterns that will be considered as newline encodings.
%This will not be checked for any overlap and will be processed sequentially.

returnChar=isa(str,'char');
str=int32(str);%convert to signed, this should not crop any valid Unicode codepoints.

if nargin<2
    %Replace CRLF, CR, and LF with -10 (in that order). That makes sure that all valid encodings of
    %newlines are replaced with the same value. This should even handle most cases of files that
    %mix the different styles, even though such mixing should never occur in a properly encoded
    %file. This considers LFCR as two line endings.
    if any(str==13)
        str=PatternReplace(str,int32([13 10]),int32(-10));
        str(str==13)=-10;
    end
    str(str==10)=-10;
else
    for n=1:numel(LineEnding)
        str=PatternReplace(str,int32(LineEnding{n}),int32(-10));
    end
end

%Split over newlines.
newlineidx=[0 find(str==-10) numel(str)+1];
c=cell(numel(newlineidx)-1,1);
for n=1:numel(c)
    s1=(newlineidx(n  )+1);
    s2=(newlineidx(n+1)-1);
    c{n}=str(s1:s2);
end

%Return to the original data type.
if returnChar
    for n=1:numel(c),c{n}=  char(c{n});end
else
    for n=1:numel(c),c{n}=uint32(c{n});end
end
end
function tf=CharIsUTF8
%This provides a single place to determine if the runtime uses UTF-8 or UTF-16 to encode chars.
%The advantage is that there is only 1 function that needs to change if and when Octave switches to
%UTF-16. This is unlikely, but not impossible.
persistent persistent_tf
if isempty(persistent_tf)
    if exist('OCTAVE_VERSION','builtin')~=0 %Octave
        %Test if Octave has switched to UTF-16 by looking if the Euro symbol is losslessly encoded
        %with char.
        w=struct('w',warning('off','all'));[w.msg,w.ID]=lastwarn;
        persistent_tf=~isequal(8364,double(char(8364)));
        warning(w.w);lastwarn(w.msg,w.ID); % Reset warning state.
    else
        persistent_tf=false;
    end
end
tf=persistent_tf;
end
function error_(options,varargin)
%Print an error to the command window, a file and/or the String property of an object.
%The error will first be written to the file and object before being actually thrown.
%
%Apart from controlling the way an error is written, you can also run a specific function. The
%'fcn' field of the options must be a struct (scalar or array) with two fields: 'h' with a function
%handle, and 'data' with arbitrary data passed as third input. These functions will be run with
%'error' as first input. The second input is a struct with identifier, message, and stack as
%fields. This function will be run with feval (meaning the function handles can be replaced with
%inline functions or anonymous functions).
%
%The intention is to allow replacement of every error(___) call with error_(options,___).
%
% NB: the error trace that is written to a file or object may differ from the trace displayed by
% calling the builtin error function. This was only observed when evaluating code sections.
%
%options.boolean.con: if true throw error with rethrow()
%options.fid:         file identifier for fprintf (array input will be indexed)
%options.boolean.fid: if true print error to file
%options.obj:         handle to object with String property (array input will be indexed)
%options.boolean.obj: if true print error to object (options.obj)
%options.fcn          struct (array input will be indexed)
%options.fcn.h:       handle of function to be run
%options.fcn.data:    data passed as third input to function to be run (optional)
%options.boolean.fnc: if true the function(s) will be run
%
%syntax:
%  error_(options,msg)
%  error_(options,msg,A1,...,An)
%  error_(options,id,msg)
%  error_(options,id,msg,A1,...,An)
%  error_(options,ME)               %equivalent to rethrow(ME)
%
%examples options struct:
%  % Write to a log file:
%  opts=struct;opts.fid=fopen('log.txt','wt');
%  % Display to a status window and bypass the command window:
%  opts=struct;opts.boolean.con=false;opts.obj=uicontrol_object_handle;
%  % Write to 2 log files:
%  opts=struct;opts.fid=[fopen('log2.txt','wt') fopen('log.txt','wt')];

persistent this_fun
if isempty(this_fun),this_fun=func2str(@error_);end

%Parse options struct, allowing an empty input to revert to default.
if isempty(options),options=validate_print_to__options(struct);end
options                   =parse_warning_error_redirect_options(  options  );
[id,msg,stack,trace,no_op]=parse_warning_error_redirect_inputs( varargin{:});
if no_op,return,end
ME=struct('identifier',id,'message',msg,'stack',stack);

%Print to object.
if options.boolean.obj
    msg_=msg;while msg_(end)==10,msg_(end)='';end%Crop trailing newline.
    if any(msg_==10)  % Parse to cellstr and prepend 'Error: '.
        msg_=char2cellstr(['Error: ' msg_]);
    else              % Only prepend 'Error: '.
        msg_=['Error: ' msg_];
    end
    for OBJ=options.obj(:).'
        try set(OBJ,'String',msg_);catch,end
    end
end

%Print to file.
if options.boolean.fid
    for FID=options.fid(:).'
        try fprintf(FID,'Error: %s\n%s',msg,trace);catch,end
    end
end

%Run function.
if options.boolean.fcn
    if ismember(this_fun,{stack.name})
        %To prevent an infinite loop, trigger an error.
        error('prevent recursion')
    end
    for FCN=options.fcn(:).'
        if isfield(FCN,'data')
            try feval(FCN.h,'error',ME,FCN.data);catch,end
        else
            try feval(FCN.h,'error',ME);catch,end
        end
    end
end

%Actually throw the error.
rethrow(ME)
end
function [str,stack]=get_trace(skip_layers,stack)
if nargin==0,skip_layers=1;end
if nargin<2, stack=dbstack;end
stack(1:skip_layers)=[];

%Parse the ML6.5 style of dbstack (the name field includes full file location).
if ~isfield(stack,'file')
    for n=1:numel(stack)
        tmp=stack(n).name;
        if strcmp(tmp(end),')')
            %Internal function.
            ind=strfind(tmp,'(');
            name=tmp( (ind(end)+1):(end-1) );
            file=tmp(1:(ind(end)-2));
        else
            file=tmp;
            [ignore,name]=fileparts(tmp); %#ok<ASGLU>
        end
        [ignore,stack(n).file]=fileparts(file); %#ok<ASGLU>
        stack(n).name=name;
    end
end

%Parse Octave style of dbstack (the file field includes full file location).
persistent IsOctave,if isempty(IsOctave),IsOctave=exist('OCTAVE_VERSION','builtin');end
if IsOctave
    for n=1:numel(stack)
        [ignore,stack(n).file]=fileparts(stack(n).file); %#ok<ASGLU>
    end
end

%Create the char array with a (potentially) modified stack.
s=stack;
c1='>';
str=cell(1,numel(s)-1);
for n=1:numel(s)
    [ignore_path,s(n).file,ignore_ext]=fileparts(s(n).file); %#ok<ASGLU>
    if n==numel(s),s(n).file='';end
    if strcmp(s(n).file,s(n).name),s(n).file='';end
    if ~isempty(s(n).file),s(n).file=[s(n).file '>'];end
    str{n}=sprintf('%c In %s%s (line %d)\n',c1,s(n).file,s(n).name,s(n).line);
    c1=' ';
end
str=horzcat(str{:});
end
function opts=parse_NameValue(default,varargin)
%Match the Name,Value pairs to the default option, ignoring incomplete names and case.
%
%If this fails to find a match, this will throw an error with the offending name as the message.

opts=default;
if nargin==1,return,end

%Unwind an input struct to Name,Value pairs.
if nargin==2
    Names=fieldnames(varargin{1});
    Values=struct2cell(varargin{1});
else
    %Wrap in cellstr to account for strings (this also deals with the fun(Name=Value) syntax).
    Names=cellstr(varargin(1:2:end));
    Values=varargin(2:2:end);
end

%Convert the real fieldnames to a char matrix.
d_Names1=fieldnames(default);d_Names2=lower(d_Names1);
len=cellfun('prodofsize',d_Names2);maxlen=max(len);
for n=find(len<maxlen).' %Pad with spaces where needed
    d_Names2{n}((end+1):maxlen)=' ';
end
d_Names2=vertcat(d_Names2{:});

%Attempt to match the names.
for n=1:numel(Names)
    name=lower(Names{n});
    tmp=d_Names2(:,1:min(end,numel(name)));
    non_matching=numel(name)-sum(cumprod(tmp==repmat(name,size(tmp,1),1),2),2);
    match_idx=find(non_matching==0);
    if numel(match_idx)~=1
        error('parse_NameValue:NonUniqueMatch',Names{n})
    end
    
    %Store the Value in the output struct.
    opts.(d_Names1{match_idx})=Values{n};
end
end
function [id,msg,stack,trace,no_op]=parse_warning_error_redirect_inputs(varargin)
no_op=false;
if nargin==1
    %  error_(options,msg)
    %  error_(options,ME)
    if isa(varargin{1},'struct') || isa(varargin{1},'MException')
        ME=varargin{1};
        if numel(ME)==0
            no_op=true;
            [id,msg,stack,trace]=deal('');
            return
        end
        try
            stack=ME.stack;%Use the original call stack if possible.
            trace=get_trace(0,stack);
        catch
            [trace,stack]=get_trace(3);
        end
        id=ME.identifier;
        msg=ME.message;
        pat='Error using <a href="matlab:matlab.internal.language.introspective.errorDocCallback(';
        %This pattern may occur when using try error(id,msg),catch,ME=lasterror;end instead of
        %catching the MException with try error(id,msg),catch ME,end.
        %This behavior is not stable enough to robustly check for it, but it only occurs with
        %lasterror, so we can use that.
        if isa(ME,'struct') && numel(msg)>numel(pat) && strcmp(pat,msg(1:numel(pat)))
            %Strip the first line (which states 'error in function (line)', instead of only msg).
            msg(1:find(msg==10,1))='';
        end
    else
        [trace,stack]=get_trace(3);
        [id,msg]=deal('',varargin{1});
    end
else
    [trace,stack]=get_trace(3);
    if ~isempty(strfind(varargin{1},'%')) %The id can't contain a percent symbol.
        %  error_(options,msg,A1,...,An)
        id='';
        A1_An=varargin(2:end);
        msg=sprintf(varargin{1},A1_An{:});
    else
        %  error_(options,id,msg)
        %  error_(options,id,msg,A1,...,An)
        id=varargin{1};
        msg=varargin{2};
        if nargin>3
            A1_An=varargin(3:end);
            msg=sprintf(msg,A1_An{:});
        end
    end
end
end
function options=parse_warning_error_redirect_options(options)
%Fill the struct:
%options.boolean.con (this field is ignored in error_)
%options.boolean.fid
%options.boolean.obj
%options.boolean.fcn
if ~isfield(options,'boolean'),options.boolean=struct;end
if ~isfield(options.boolean,'con') || isempty(options.boolean.con)
    options.boolean.con=false;
end
if ~isfield(options.boolean,'fid') || isempty(options.boolean.fid)
    options.boolean.fid=isfield(options,'fid');
end
if ~isfield(options.boolean,'obj') || isempty(options.boolean.obj)
    options.boolean.obj=isfield(options,'obj');
end
if ~isfield(options.boolean,'fcn') || isempty(options.boolean.fcn)
    options.boolean.fcn=isfield(options,'fcn');
end
end
function out=PatternReplace(in,pattern,rep)
%Functionally equivalent to strrep, but extended to more data types.
out=in(:)';
if numel(pattern)==0
    L=false(size(in));
elseif numel(rep)>numel(pattern)
    error('not implemented (padding required)')
else
    L=true(size(in));
    for n=1:numel(pattern)
        k=find(in==pattern(n));
        k=k-n+1;k(k<1)=[];
        %Now k contains the indices of the beginning of each match.
        L2=false(size(L));L2(k)=true;
        L= L & L2;
        if ~any(L),break,end
    end
end
k=find(L);
if ~isempty(k)
    for n=1:numel(rep)
        out(k+n-1)=rep(n);
    end
    if numel(rep)==0,n=0;end
    if numel(pattern)>n
        k=k(:);%Enforce direction.
        remove=(n+1):numel(pattern);
        idx=bsxfun_plus(k,remove-1);
        out(idx(:))=[];
    end
end
end
function [isLogical,val]=test_if_scalar_logical(val)
%Test if the input is a scalar logical or convertible to it.
%The char and string test are not case sensitive.
%(use the first output to trigger an input error, use the second as the parsed input)
%
% Allowed values:
%- true or false
%- 1 or 0
%- 'on' or 'off'
%- matlab.lang.OnOffSwitchState.on or matlab.lang.OnOffSwitchState.off
%- 'enable' or 'disable'
%- 'enabled' or 'disabled'
persistent states
if isempty(states)
    states={true,false;...
        1,0;...
        'on','off';...
        'enable','disable';...
        'enabled','disabled'};
    try
        states(end+1,:)=eval('{"on","off"}');
    catch
    end
end
isLogical=true;
try
    if isa(val,'char') || isa(val,'string')
        try val=lower(val);catch,end
    end
    for n=1:size(states,1)
        for m=1:2
            if isequal(val,states{n,m})
                val=states{1,m};return
            end
        end
    end
    if isa(val,'matlab.lang.OnOffSwitchState')
        val=logical(val);return
    end
catch
end
isLogical=false;
end
function str=unicode_to_char(unicode,encode_as_UTF16)
%Encode Unicode code points with UTF-16 on Matlab and UTF-8 on Octave.
%Input is either implicitly or explicitly converted to a row-vector.

persistent isOctave,if isempty(isOctave),isOctave = exist('OCTAVE_VERSION', 'builtin') ~= 0;end
if nargin==1
    encode_as_UTF16=~CharIsUTF8;
end
if encode_as_UTF16
    if all(unicode<65536)
        str=uint16(unicode);
        str=reshape(str,1,numel(str));%Convert explicitly to a row-vector.
    else
        %Encode as UTF-16.
        [char_list,ignore,positions]=unique(unicode); %#ok<ASGLU>
        str=cell(1,numel(unicode));
        for n=1:numel(char_list)
            str_element=unicode_to_UTF16(char_list(n));
            str_element=uint16(str_element);
            str(positions==n)={str_element};
        end
        str=cell2mat(str);
    end
    if ~isOctave
        str=char(str);%Conversion to char could trigger a conversion range error in Octave.
    end
else
    if all(unicode<128)
        str=char(unicode);
        str=reshape(str,1,numel(str));%Convert explicitly to a row-vector.
    else
        %Encode as UTF-8
        [char_list,ignore,positions]=unique(unicode); %#ok<ASGLU>
        str=cell(1,numel(unicode));
        for n=1:numel(char_list)
            str_element=unicode_to_UTF8(char_list(n));
            str_element=uint8(str_element);
            str(positions==n)={str_element};
        end
        str=cell2mat(str);
        str=char(str);
    end
end
end
function str=unicode_to_UTF16(unicode)
%Convert a single character to UTF-16 bytes.
%
%The value of the input is converted to binary and padded with 0 bits at the front of the string to
%fill all 'x' positions in the scheme.
%See https://en.wikipedia.org/wiki/UTF-16
%
% 1 word (U+0000 to U+D7FF and U+E000 to U+FFFF):
%  xxxxxxxx_xxxxxxxx
% 2 words (U+10000 to U+10FFFF):
%  110110xx_xxxxxxxx 110111xx_xxxxxxxx
if unicode<65536
    str=unicode;return
end
U=double(unicode)-65536;%Convert to double for ML6.5.
U=dec2bin(U,20);
str=bin2dec(['110110' U(1:10);'110111' U(11:20)]).';
end
function str=unicode_to_UTF8(unicode)
%Convert a single character to UTF-8 bytes.
%
%The value of the input is converted to binary and padded with 0 bits at the front of the string to
%fill all 'x' positions in the scheme.
%See https://en.wikipedia.org/wiki/UTF-8
if numel(unicode)>1,error('this should only be used for single characters'),end
if unicode<128
    str=unicode;return
end
persistent pers
if isempty(pers)
    pers=struct;
    pers.limits.lower=hex2dec({'0000','0080','0800', '10000'});
    pers.limits.upper=hex2dec({'007F','07FF','FFFF','10FFFF'});
    pers.scheme{2}='110xxxxx10xxxxxx';
    pers.scheme{2}=reshape(pers.scheme{2}.',8,2);
    pers.scheme{3}='1110xxxx10xxxxxx10xxxxxx';
    pers.scheme{3}=reshape(pers.scheme{3}.',8,3);
    pers.scheme{4}='11110xxx10xxxxxx10xxxxxx10xxxxxx';
    pers.scheme{4}=reshape(pers.scheme{4}.',8,4);
    for b=2:4
        pers.scheme_pos{b}=find(pers.scheme{b}=='x');
        pers.bits(b)=numel(pers.scheme_pos{b});
    end
end
bytes=find(pers.limits.lower<=unicode & unicode<=pers.limits.upper);
str=pers.scheme{bytes};
scheme_pos=pers.scheme_pos{bytes};
b=dec2bin(unicode,pers.bits(bytes));
str(scheme_pos)=b;
str=bin2dec(str.').';
end
function unicode=UTF16_to_unicode(UTF16)
%Convert UTF-16 to the code points stored as uint32
%
%See https://en.wikipedia.org/wiki/UTF-16
%
% 1 word (U+0000 to U+D7FF and U+E000 to U+FFFF):
%  xxxxxxxx_xxxxxxxx
% 2 words (U+10000 to U+10FFFF):
%  110110xx_xxxxxxxx 110111xx_xxxxxxxx

persistent isOctave,if isempty(isOctave),isOctave = exist('OCTAVE_VERSION', 'builtin') ~= 0;end
UTF16=uint32(UTF16);

multiword= UTF16>55295 & UTF16<57344; %0xD7FF and 0xE000
if ~any(multiword)
    unicode=UTF16;return
end

word1= find( UTF16>=55296 & UTF16<=56319 );
word2= find( UTF16>=56320 & UTF16<=57343 );
try
    d=word2-word1;
    if any(d~=1) || isempty(d)
        error('trigger error')
    end
catch
    error('input is not valid UTF-16 encoded')
end

%Binary header:
% 110110xx_xxxxxxxx 110111xx_xxxxxxxx
% 00000000 01111111 11122222 22222333
% 12345678 90123456 78901234 56789012
header_bits='110110110111';header_locs=[1:6 17:22];
multiword=UTF16([word1.' word2.']);
multiword=unique(multiword,'rows');
S2=mat2cell(multiword,ones(size(multiword,1),1),2);
unicode=UTF16;
for n=1:numel(S2)
    bin=dec2bin(double(S2{n}))';
    
    if ~strcmp(header_bits,bin(header_locs))
        error('input is not valid UTF-16 encoded')
    end
    bin(header_locs)='';
    if ~isOctave
        S3=uint32(bin2dec(bin  ));
    else
        S3=uint32(bin2dec(bin.'));%Octave needs an extra transpose.
    end
    S3=S3+65536;% 0x10000
    %Perform actual replacement.
    unicode=PatternReplace(unicode,S2{n},S3);
end
end
function [unicode,isUTF8,assumed_UTF8]=UTF8_to_unicode(UTF8,print_to)
%Convert UTF-8 to the code points stored as uint32
%Plane 16 goes up to 10FFFF, so anything larger than uint16 will be able to hold every code point.
%
%If there a second output argument, this function will not return an error if there are encoding
%error. The second output will contain the attempted conversion, while the first output will
%contain the original input converted to uint32.
%
%The second input can be used to also print the error to a GUI element or to a text file.
if nargin<2,print_to=[];end
return_on_error= nargout==1 ;

UTF8=uint32(UTF8);
[assumed_UTF8,flag,ME]=UTF8_to_unicode_internal(UTF8,return_on_error);
if strcmp(flag,'success')
    isUTF8=true;
    unicode=assumed_UTF8;
elseif strcmp(flag,'error')
    isUTF8=false;
    if return_on_error
        error_(print_to,ME)
    end
    unicode=UTF8;%Return input unchanged (apart from casting to uint32).
end
end
function [UTF8,flag,ME]=UTF8_to_unicode_internal(UTF8,return_on_error)

flag='success';
ME=struct('identifier','HJW:UTF8_to_unicode:notUTF8','message','Input is not UTF-8.');

persistent isOctave,if isempty(isOctave),isOctave = exist('OCTAVE_VERSION', 'builtin') ~= 0;end

if any(UTF8>255)
    flag='error';
    if return_on_error,return,end
elseif all(UTF8<128)
    return
end

for bytes=4:-1:2
    val=bin2dec([repmat('1',1,bytes) repmat('0',1,8-bytes)]);
    multibyte=UTF8>=val & UTF8<256;%Exclude the already converted chars.
    if any(multibyte)
        multibyte=find(multibyte);multibyte=multibyte(:).';
        if numel(UTF8)<(max(multibyte)+bytes-1)
            flag='error';
            if return_on_error,return,end
            multibyte( (multibyte+bytes-1)>numel(UTF8) )=[];
        end
        if ~isempty(multibyte)
            idx=bsxfun_plus(multibyte , (0:(bytes-1)).' );
            idx=idx.';
            multibyte=UTF8(idx);
        end
    else
        multibyte=[];
    end
    header_bits=[repmat('1',1,bytes-1) repmat('10',1,bytes)];
    header_locs=unique([1:(bytes+1) 1:8:(8*bytes) 2:8:(8*bytes)]);
    if numel(multibyte)>0
        multibyte=unique(multibyte,'rows');
        S2=mat2cell(multibyte,ones(size(multibyte,1),1),bytes);
        for n=1:numel(S2)
            bin=dec2bin(double(S2{n}))';
            %To view the binary data, you can use this: bin=bin(:)';
            %Remove binary header (3 byte example):
            %1110xxxx10xxxxxx10xxxxxx
            %    xxxx  xxxxxx  xxxxxx
            if ~strcmp(header_bits,bin(header_locs))
                %Check if the byte headers match the UTF-8 standard.
                flag='error';
                if return_on_error,return,end
                continue %leave unencoded
            end
            bin(header_locs)='';
            if ~isOctave
                S3=uint32(bin2dec(bin  ));
            else
                S3=uint32(bin2dec(bin.'));%Octave needs an extra transpose.
            end
            %Perform actual replacement.
            UTF8=PatternReplace(UTF8,S2{n},S3);
        end
    end
end
end
function [opts,ME]=validate_print_to__options(opts_in,ME)
%If any input is invalid, this returns an empty array and sets ME.message.
%
%Input struct:
%options.print_to_con=true;   % or false
%options.print_to_fid=fid;    % or []
%options.print_to_obj=h_obj;  % or []
%options.print_to_fcn=struct; % or []
%
%Output struct:
%options.fid
%options.obj
%options.fcn.h
%options.fcn.data
%options.boolean.con
%options.boolean.fid
%options.boolean.obj
%options.boolean.fcn

%Set defaults.
if nargin<2,ME=struct;end
if ~isfield(opts_in,'print_to_con'),opts_in.print_to_con=[];end
if ~isfield(opts_in,'print_to_fid'),opts_in.print_to_fid=[];end
if ~isfield(opts_in,'print_to_obj'),opts_in.print_to_obj=[];end
if ~isfield(opts_in,'print_to_fcn'),opts_in.print_to_fcn=[];end
print_to_con_default=true; % Unless a valid fid, obj, or fcn is specified.

%Initalize output.
opts=struct;

%Parse the fid. We can use ftell to determine if fprintf is going to fail.
item=opts_in.print_to_fid;
if isempty(item)
    opts.boolean.fid=false;
else
    print_to_con_default=false;
    opts.boolean.fid=true;
    opts.fid=item;
    for n=1:numel(item)
        try position=ftell(item(n));catch,position=-1;end
        if item(n)~=1 && position==-1
            ME.message=['Invalid print_to_fid parameter:',char(10),...
                'should be a valid file identifier or 1.']; %#ok<CHARTEN>
            opts=[];return
        end
    end
end

%Parse the object handle. Retrieving from multiple objects at once works, but writing that output
%back to multiple objects doesn't work if Strings are dissimilar.
item=opts_in.print_to_obj;
if isempty(item)
    opts.boolean.obj=false;
else
    print_to_con_default=false;
    opts.boolean.obj=true;
    opts.obj=item;
    for n=1:numel(item)
        try
            txt=get(item(n),'String'    ); %See if this triggers an error.
            set(    item(n),'String','' ); %Test if property is writeable.
            set(    item(n),'String',txt); %Restore original content.
        catch
            ME.message=['Invalid print_to_obj parameter:',char(10),...
                'should be a handle to an object with a writeable String property.']; %#ok<CHARTEN>
            opts=[];return
        end
    end
end

%Parse the function handles.
item=opts_in.print_to_fcn;
if isempty(item)
    opts.boolean.fcn=false;
else
    print_to_con_default=false;
    try
        for n=1:numel(item)
            if ~ismember(class(item(n).h),{'function_handle','inline'}) ...
                    || numel(item(n).h)~=1
                error('trigger error')
            end
        end
    catch
        ME.message=['Invalid print_to_fcn parameter:',char(10),...
            'should be a struct with the h field containing a function handle,',char(10),...
            'anonymous function or inline function.']; %#ok<CHARTEN>
        opts=[];return
    end
end

%Parse the logical that determines if a warning will be printed to the command window.
%This is true by default, unless an fid, obj, or fcn is specified.
item=opts_in.print_to_con;
if isempty(item)
    opts.boolean.con=print_to_con_default;
else
    [passed,opts.boolean.con]=test_if_scalar_logical(item);
    if ~passed
        ME.message=['Invalid print_to_con parameter:',char(10),...
            'should be a scalar logical.']; %#ok<CHARTEN>
        opts=[];return
    end
end
end