{   USBPROG_TEST
*
*   Production test program for Embed Inc PIC programmers.  The following
*   programmers are supported:
*
*     USBProg
*     USBProg2
*     LProg
}
program usbprog_test;
%include 'sys.ins.pas';
%include 'util.ins.pas';
%include 'string.ins.pas';
%include 'file.ins.pas';
%include 'stuff.ins.pas';
%include 'picprg.ins.pas';

const
  max_msg_parms = 3;                   {max parameters we can pass to a message}
  seqdir = '(cog)progs/usbprog_test';  {name of dir with serial number sequence files}

type
  prog_k_t = (                         {type of programmer being tested}
    prog_usbprog_k,                    {USBProg}
    prog_usbprog2_k,                   {USBProg2}
    prog_lprog_k);                     {LProg}

var
  toolser: sys_int_machine_t;          {serial number of programmer to use, not test}
  toolname:                            {full name string of programmer to use, not test}
    %include '(cog)lib/string80.ins.pas';
  toolfw: picprg_fw_t;                 {info about tool programmer firmware}
  pr: picprg_t;                        {state of one use of the PICPRG library}
  ntry: sys_int_machine_t;             {1-N number of attempt to perform operation}
  ser: sys_int_machine_t;              {serial number to assign to unit under test}
  board: sys_int_machine_t;            {board revision number of target unit}
  proto: sys_int_machine_t;            {1-N prototype version, 0 = production version}
  tmode: sys_int_machine_t;            {test mode ID for compatibility with tester}
  ok: boolean;                         {true/false status from separately run program}
  exstat: sys_sys_exstat_t;            {exit status from separately run program}
  prog: prog_k_t;                      {type of programmer being tested}
  pass: boolean;                       {all target operations performed normally}
  picprg_isopen: boolean;              {PICPRG library is open using PR}
  tk:                                  {scratch token}
    %include '(cog)lib/string32.ins.pas';
  cont:                                {prompt string to press ENTER to continue}
    %include '(cog)lib/string80.ins.pas';
  buf:                                 {one line user input/output buffer}
    %include '(cog)lib/string8192.ins.pas';
  devname:                             {normal device name without serial number}
    %include '(cog)lib/string80.ins.pas';
  sfnam:                               {unit under test serial number sequence file name}
    %include '(cog)lib/string_treename.ins.pas';
  cmd:                                 {command to execute}
    %include '(cog)lib/string8192.ins.pas';

  opt:                                 {upcased command line option}
    %include '(cog)lib/string_treename.ins.pas';
  parm:                                {command line option parameter}
    %include '(cog)lib/string_treename.ins.pas';
  pick: sys_int_machine_t;             {number of token picked from list}
  msg_parm:                            {references arguments passed to a message}
    array[1..max_msg_parms] of sys_parm_msg_t;
  stat: sys_err_t;                     {completion status code}

label
  next_opt, err_parm, parm_bad, done_opts,
  loop_toolnum, loop_target, fail, loop_prog8v, done_prog8v, loop_prog17v,
  done_prog17v, loop_progctrl, done_testmode, retry_after_test;

begin
{
*   Initialize before reading the command line.
}
  string_cmline_init;                  {init for reading the command line}
  prog := prog_usbprog_k;              {init to testing a USBProg}
  board := 1;                          {init to board version 1}
  proto := 0;                          {init to production version}
{
*   Back here each new command line option.
}
next_opt:
  string_cmline_token (opt, stat);     {get next command line option name}
  if string_eos(stat) then goto done_opts; {exhausted command line ?}
  sys_error_abort (stat, 'string', 'cmline_opt_err', nil, 0);
  string_upcase (opt);                 {make upper case for matching list}
  string_tkpick80 (opt,                {pick command line option name from list}
    '-PROG -BOARD -PROTO',
    pick);                             {number of keyword picked from list}
  case pick of                         {do routine for specific option}
{
*   -PROG type
}
1: begin
  string_cmline_token (parm, stat);
  if sys_error(stat) then goto err_parm;
  string_upcase (parm);                {make upper case for keyword matching}
  string_tkpick80 (parm,
    'USBPROG USBPROG2 LPROG',
    pick);
  case pick of
1:  prog := prog_usbprog_k;
2:  prog := prog_usbprog2_k;
3:  prog := prog_lprog_k;
otherwise
    goto err_parm;
    end;
  end;
{
*   -BOARD version
}
2: begin
  string_cmline_token_int (board, stat);
  end;
{
*   -PROTO version
}
3: begin
  string_cmline_token_int (proto, stat);
  end;
{
*   Unrecognized command line option.
}
otherwise
    string_cmline_opt_bad;             {unrecognized command line option}
    end;                               {end of command line option case statement}

err_parm:                              {jump here on error with parameter}
  string_cmline_parm_check (stat, opt); {check for bad command line option parameter}
  goto next_opt;                       {back for next command line option}

parm_bad:                              {jump here on got illegal parameter}
  string_cmline_reuse;                 {re-read last command line token next time}
  string_cmline_token (parm, stat);    {re-read the token for the bad parameter}
  sys_msg_parm_vstr (msg_parm[1], parm);
  sys_msg_parm_vstr (msg_parm[2], opt);
  sys_message_bomb ('string', 'cmline_parm_bad', msg_parm, 2);

done_opts:                             {done with all the command line options}
{
*   Done with the command line options.
}
  case prog of                         {which programmer are we testing ?}
  {
  *   The following state is set depending on the target programmer type:
  *
  *     DEVNAME  -  Default device name without the serial number.
  *
  *     BUF  -  Generic name of sequence number file to get serial number from.
  }
prog_usbprog_k: begin
      string_vstring (devname, 'USBProg'(0), -1);
      string_vstring (buf, 'usbprog'(0), -1);
      end;
prog_usbprog2_k: begin
      string_vstring (devname, 'USBProg'(0), -1);
      string_vstring (buf, 'usbprog'(0), -1);
      end;
prog_lprog_k: begin
      string_vstring (devname, 'LProg'(0), -1);
      string_vstring (buf, 'lprog'(0), -1);
      end;
otherwise
    writeln ('INTERNAL ERROR: unexpected programmer type.');
    sys_bomb;
    end;

  string_vstring (sfnam, seqdir, size_char(seqdir)); {init seq file name to directory}
  string_append1 (sfnam, '/');
  string_append (sfnam, buf);          {add generic sequence file name}

  string_f_message (                   {save prompt string for pressing ENTER to continue}
    cont, 'picprg', 'utest_continue', nil, 0);
  string_append1 (cont, ' ');

  picprg_isopen := false;              {we don't have PICPRG library open}
{
*   Get the serial number of the programmer that will be used to program the
*   target, and use it to make the full programmer name.  This section sets
*   the following state:
*
*     TOOLNAME - Full name of programmer used as tool, case sensitive.
*
*     TOOLFW   - PICPRG library firmware info of the tool programmer.
}
loop_toolnum:                          {back here until have tool programmer name}
  if picprg_isopen then begin          {PICPRG library is open ?}
    picprg_close (pr, stat);           {close it}
    end;

  writeln;
  string_f_message (                   {get string asking for tool programmer serial number}
    buf,                               {returned string}
    'picprg', 'utest_toolser_get',     {message subsystem and name}
    nil, 0);                           {parameters for the message}
  string_append1 (buf, ' ');
  string_prompt (buf);                 {ask for the tool programmer serial number}

  string_readin (buf);                 {get the response}
  string_t_int (buf, toolser, stat);
  if sys_error(stat) then begin        {couldn't convert to integer}
    sys_error_print (stat, '', '', nil, 0);
    goto loop_toolnum;
    end;
  if (toolser < 1) or (toolser > 9999) then begin {out of range tool serial number ?}
    sys_msg_parm_int (msg_parm[1], toolser);
    sys_message_parms ('picprg', 'utest_toolser_bad', msg_parm, 1);
    goto loop_toolnum;
    end;

  string_vstring (toolname, 'USBProg'(0), -1); {init tool programmer name}
  string_f_int_max_base (              {make serial number digits}
    tk, toolser, 10, 4, [string_fi_leadz_k, string_fi_unsig_k], stat);
  if sys_error_check (stat, '', '', nil, 0) then goto loop_toolnum;
  string_append (toolname, tk);

  picprg_init (pr);                    {init PICPRG library state}
  pr.devconn := picprg_devconn_enum_k; {open enumeratable named device}
  string_copy (toolname, pr.prgname);  {set name of programmer to open}
  picprg_open (pr, stat);              {try to open library using tool programmer}
  if sys_error_check (stat, '', '', nil, 0) then goto loop_toolnum;
  picprg_isopen := true;               {indicate PICPRG library is open}
  picprg_fwinfo (pr, toolfw, stat);    {get info about tool programmer firmware}
  if sys_error_check (stat, '', '', nil, 0) then goto loop_toolnum;
  picprg_off (pr, stat);               {turn off all outputs}
  if sys_error_check (stat, '', '', nil, 0) then goto loop_toolnum;
  picprg_close (pr, stat);             {disconnect from tool programmer}
  if sys_error_check (stat, '', '', nil, 0) then goto loop_toolnum;
  picprg_isopen := false;              {PICPRG library is now closed}

  if toolfw.org <> picprg_org_official_k then begin {not official firmware ?}
    sys_message_parms ('picprg', 'utest_fwbad', nil, 0);
    goto loop_toolnum;
    end;

  string_copy (pr.prgname, toolname);  {save name of tool programmer}
  sys_msg_parm_vstr (msg_parm[1], toolname); {tool name}
  sys_msg_parm_vstr (msg_parm[2], toolfw.idname); {tool type}
  sys_msg_parm_int (msg_parm[3], toolfw.vers); {tool firmware version}
  sys_message_parms ('picprg', 'utest_toolinfo', msg_parm, 3);
{
*********************
*
*   Back here each new target to program and test.
}
loop_target:
  pass := true;                        {init to previous device under test passed}

fail:                                  {abort to here when target has failed}
  if picprg_isopen then begin          {PICPRG library is open ?}
    picprg_close (pr, stat);           {close it}
    end;

  if not pass then begin
    writeln;
    sys_message ('picprg', 'utest_fail');
    sys_beep (0.500, 0.000, 1);
    sys_wait (1.000);
    end;

  pass := false;                       {init to this target not passed}
  writeln;
  writeln;
  writeln;
  writeln ('----------------------------------------');
  sys_message ('picprg', 'utest_start');
{
*   Program the 8V power supply processor.
}
  case prog of
prog_usbprog_k: ;
prog_usbprog2_k: ;
otherwise
    goto done_prog8v;
    end;

  ntry := 0;                           {init number of attempt to perform this operation}
loop_prog8v:
  if ntry >= 3 then goto fail;         {hit retry limit ?}
  ntry := ntry + 1;                    {make 1-N number of this try}

  writeln;
  sys_message ('picprg', 'utest_prog8v');
  string_prompt (cont);                {press ENTER to continue}
  string_readin (buf);

  string_vstring (buf, 'pic_prog -pic 10F204 -hex (cog)src/picprg/eusb8v03 -n '(0), -1);
  string_append (buf, toolname);
  sys_run_wait_stdsame (               {run program to perform the programming operation}
    buf,                               {command to run}
    ok, exstat,                        {status returned by program}
    stat);
  sys_error_abort (stat, '', '', nil, 0);
  if exstat <> 0 then goto loop_prog8v; {failed, go back and try again ?}

done_prog8v:
{
*   Program the 17V power supply processor.
}
  case prog of
prog_usbprog_k: ;
prog_usbprog2_k: ;
otherwise
    goto done_prog17v;
    end;

  ntry := 0;                           {init number of attempt to perform this operation}
loop_prog17v:
  if ntry >= 3 then goto fail;         {hit retry limit ?}
  ntry := ntry + 1;                    {make 1-N number of this try}

  writeln;
  sys_message ('picprg', 'utest_prog17v');
  string_prompt (cont);                {press ENTER to continue}
  string_readin (buf);

  string_vstring (buf, 'pic_prog -pic 10F204 -hex (cog)src/picprg/eusb17v02 -n '(0), -1);
  string_append (buf, toolname);
  sys_run_wait_stdsame (               {run program to perform the programming operation}
    buf,                               {command to run}
    ok, exstat,                        {status returned by program}
    stat);
  sys_error_abort (stat, '', '', nil, 0);
  if exstat <> 0 then goto loop_prog17v; {failed, go back and try again ?}

done_prog17v:
{
*   Program the main control processor.
}
  string_vstring (cmd, 'pic_prog -n '(0), -1); {build command line string}
  string_append (cmd, toolname);
  case prog of
prog_lprog_k: begin
      string_appends (cmd, ' -hex (cog)src/picprg/lprg11 -pic '(0));
      if proto = 0
        then string_appends (cmd, '18F2455')
        else string_appends (cmd, '18F2550');
      end;
otherwise
    string_appends (cmd, ' -pic 18F2550 -hex (cog)src/picprg/eusb35'(0));
    end;

  ntry := 0;                           {init number of attempt to perform this operation}
loop_progctrl:
  if ntry >= 3 then goto fail;         {hit retry limit ?}
  ntry := ntry + 1;                    {make 1-N number of this try}

  writeln;
  case prog of
prog_lprog_k: begin
      sys_message ('picprg', 'utest_progctrl_lprog');
      end;
otherwise
    sys_message ('picprg', 'utest_progctrl');
    end;
  string_prompt (cont);                {press ENTER to continue}
  string_readin (buf);

  sys_run_wait_stdsame (               {run program to perform the programming operation}
    cmd,                               {command to run}
    ok, exstat,                        {status returned by program}
    stat);
  sys_error_abort (stat, '', '', nil, 0);
  if exstat <> 0 then goto loop_progctrl; {failed, go back and try again ?}
{
*   Set the test mode for compatibility with the tester.
}
  tmode := -1;                         {init to invalid test mode}
  case prog of
prog_lprog_k: begin
      tmode := 0;                      {test mode required by tester}
      end;
    end;
  if tmode < 0 then goto done_testmode;
  {
  *   Tell user to connect the UUT to the USB.
  }
  writeln;
  sys_message ('picprg', 'utest_connect_usb');
  string_f_message (buf, 'picprg', 'utest_continue', nil, 0);
  string_append1 (buf, ' ');
  string_prompt (buf);                 {press ENTER to continue}
  string_readin (tk);
  {
  *   Set the test mode to TMODE.
  }
  writeln;
  picprg_init (pr);                    {init PICPRG library state}
  pr.devconn := picprg_devconn_enum_k; {open enumeratable named device}
  string_copy (devname, pr.prgname);   {name of programmer to connect to}
  picprg_open (pr, stat);              {open library to device under test}
  if sys_stat_match (picprg_subsys_k, picprg_stat_namprognf_k, stat)
    then goto fail;
  if sys_error_check (stat, '', '', nil, 0) then goto fail;
  picprg_isopen := true;               {flag that PICPRG library is now open}
  picprg_off (pr, stat);               {make sure all outputs are off}
  if sys_error_check (stat, '', '', nil, 0) then goto fail;
  picprg_cmdw_testset (pr, tmode, stat); {set the test mode}
  if sys_error_check (stat, '', '', nil, 0) then goto fail;
  picprg_cmdw_reboot (pr, stat);       {reboot for test mode to take effect}
  picprg_close (pr, stat);             {close the PICPRG library}
  sys_error_none (stat);               {ignore errors, REBOOT causes a USB disconnect}
  picprg_isopen := false;              {indicate PICPRG library not open}

done_testmode:                         {skip to here to not set test mode}
{
*   Test the programmer using the tester.
}
  writeln;
  case prog of
prog_lprog_k: begin
      sys_message ('picprg', 'utest_tester_run_lprog');
      end;
otherwise
    sys_message ('picprg', 'utest_tester_run');
    end;
  string_f_message (buf, 'picprg', 'utest_tester_done', nil, 0);
  string_append1 (buf, ' ');
  string_prompt (buf);                 {press ENTER when tests done}
  string_readin (tk);
{
*   Verify that the unit responds to the USB and set its serial number if so.
}
  {
  *   Connect to the target programmer.  The tester set its name to "Passed" if
  *   all tests passed.
  }
  writeln;
  ntry := 0;                           {init number of previous attempt}
retry_after_test:                      {try again to connect to the programmer under test}
  ntry := ntry + 1;                    {make number of this attempt}
  picprg_init (pr);                    {init PICPRG library state}
  pr.devconn := picprg_devconn_enum_k; {open enumeratable named device}
  string_vstring (pr.prgname, 'Passed'(0), -1); {name of target if tests passed}
  picprg_open (pr, stat);              {open library to device under test}
  if sys_stat_match (picprg_subsys_k, picprg_stat_namprognf_k, stat)
    then goto fail;
  if sys_error_check (stat, '', '', nil, 0) then goto fail;
  picprg_isopen := true;               {flag that PICPRG library is now open}
  picprg_off (pr, stat);               {make sure all outputs are off}
  if sys_error_check (stat, '', '', nil, 0) then goto fail;
  if pr.fwinfo.cmd[71] then begin      {TESTGET command is implemented ?}
    picprg_cmdw_testget (pr, tmode, stat); {get current test mode}
    if sys_error_check (stat, '', '', nil, 0) then goto fail;
    if tmode <> 255 then begin         {not normal operating mode ?}
      if ntry > 1 then goto fail;      {already tried to set operating mode before ?}
      picprg_cmdw_testset (pr, 255, stat); {set to normal operating mode}
      if sys_error_check (stat, '', '', nil, 0) then goto fail;
      picprg_cmdw_reboot (pr, stat);   {reboot to make sure new test mode takes effect}
      picprg_close (pr, stat);         {close connection to programmer}
      sys_error_none (stat);           {ingnore errors, REBOOT causes a USB disconnect}
      picprg_isopen := false;          {PICPRG library not open}
      sys_wait (1.500);                {give programmer time to come back on the USB}
      goto retry_after_test;           {back and try to connect to programmer again}
      end;
    end;
  {
  *   Get the serial number string to assign to this programmer into TK.
  }
  ser := string_seq_get (              {get sequential number to make serial num from}
    sfnam,                             {sequence file name}
    1,                                 {increment to apply after getting number}
    100,                               {initial value if file not exist}
    [],                                {get the number before increment}
    stat);
  if sys_error_check (stat, '', '', nil, 0) then goto fail;
  string_f_int_max_base (              {make 4 digit serial number string}
    tk, ser, 10, 4, [string_fi_leadz_k, string_fi_unsig_k], stat);
  if sys_error_check (stat, '', '', nil, 0) then begin
    discard( string_seq_get (          {try to roll back serial number}
      sfnam, -1, 101, [], stat) );
    goto fail;
    end;
  {
  *   Set the final programmer name using the serial number string in TK.
  }
  sys_msg_parm_vstr (msg_parm[1], tk);
  sys_message_parms ('picprg', 'utest_sernum', msg_parm, 1);
  string_copy (devname, buf);          {make final name for this target}
  string_append (buf, tk);
  picprg_cmdw_nameset (pr, buf, stat); {set the name of the target unit}
  if sys_error_check (stat, '', '', nil, 0) then goto fail;
  picprg_cmdw_reboot (pr, stat);       {reboot control processor, make name take effect}
  picprg_close (pr, stat);             {may fail due to reboot}
  picprg_isopen := false;              {indicate PICPRG library no longer open}

  writeln;
  sys_message ('picprg', 'utest_pass');
  goto loop_target;                    {back to do next target unit}
  end.
