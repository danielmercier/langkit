## vim: filetype=makoada

with Ada.Calendar;              use Ada.Calendar;
with Ada.Containers.Vectors;
with Ada.Strings;               use Ada.Strings;
with Ada.Strings.Unbounded;     use Ada.Strings.Unbounded;
pragma Warnings (Off, "internal");
with Ada.Strings.Unbounded.Aux; use Ada.Strings.Unbounded.Aux;
with Ada.Text_IO;               use Ada.Text_IO;

with Interfaces; use Interfaces;

with GNAT.Command_Line; use GNAT.Command_Line;
with GNAT.Strings;

with Langkit_Support.Bump_Ptr;           use Langkit_Support.Bump_Ptr;
with Langkit_Support.Diagnostics;        use Langkit_Support.Diagnostics;
with Langkit_Support.Symbols;            use Langkit_Support.Symbols;
with Langkit_Support.Token_Data_Handler;
use Langkit_Support.Token_Data_Handler;
with Langkit_Support.Tokens;             use Langkit_Support.Tokens;

with ${_self.ada_api_settings.lib_name}.Analysis;
use ${_self.ada_api_settings.lib_name}.Analysis;
with ${_self.ada_api_settings.lib_name}.AST_Root;
use ${_self.ada_api_settings.lib_name}.AST_Root;
with ${_self.ada_api_settings.lib_name}.AST;
use ${_self.ada_api_settings.lib_name}.AST;
with ${_self.ada_api_settings.lib_name}.AST.Parsers;
use ${_self.ada_api_settings.lib_name}.AST.Parsers;
with ${_self.ada_api_settings.lib_name}.Init;
use ${_self.ada_api_settings.lib_name}.Init;

procedure Parse is

   function "+" (S : String) return Unbounded_String renames
      To_Unbounded_String;

   package String_Vectors is new Ada.Containers.Vectors
     (Natural, Unbounded_String);

   Config     : Command_Line_Configuration;
   Silent     : aliased Boolean;
   Measure_Time, Do_Print_Trivia : aliased Boolean;
   Rule_Name  : aliased GNAT.Strings.String_Access :=
      new String'("${get_context().main_rule_name}");
   Charset    : aliased GNAT.Strings.String_Access :=
      new String'("iso-8859-1");
   File_Name  : aliased GNAT.Strings.String_Access;
   File_List  : aliased GNAT.Strings.String_Access;
   Print_Envs : aliased Boolean;

   Input_Str : Unbounded_String;
   Lookups : String_Vectors.Vector;

   ------------------
   -- Process_Node --
   ------------------

   procedure Process_Node (Res : in out ${root_node_type_name}) is
   begin
      if Res = null then
         Put_Line ("<null node>");
         return;
      end if;

      Res.Validate;
      if not Silent then
         if Do_Print_Trivia then
            PP_Trivia (Res);
         else
            Res.Print;
         end if;
      end if;

      for Lookup_Str of Lookups loop
         New_Line;

         declare
            Sep : constant Natural := Index (Lookup_Str, ":");

            Line : Unsigned_32 := Unsigned_32'Value
              (Slice (Lookup_Str, 1, Sep - 1));
            Column : Unsigned_16 := Unsigned_16'Value
              (Slice (Lookup_Str, Sep + 1, Length (Lookup_Str)));

            Sloc : constant Source_Location := (Line, Column);
            Lookup_Res : ${root_node_type_name} :=
               Lookup (${root_node_type_name} (Res), (Line, Column));
         begin
            Put_Line ("Lookup " & Image (Sloc) & ":");
            Lookup_Res.Print;
         end;
      end loop;
   end Process_Node;

   -----------------
   -- Parse_Input --
   -----------------

   procedure Parse_Input is
      Input_Str_Ptr    : Big_String_Access;
      Input_Str_Length : Natural;

      TDH     : Token_Data_Handler;
      Symbols : Symbol_Table := Create;
      Parser  : Parser_Type;
      Pool    : Bump_Ptr_Pool := Create;
   begin
      Initialize (TDH, Symbols);

      Get_String (Input_Str, Input_Str_Ptr, Input_Str_Length);
      Parser := Create_From_Buffer
        (Input_Str_Ptr (1 .. Input_Str_Length), "",
         TDH'Unrestricted_Access,
         --  Parse with trivia if we want to print it ultimately
         With_Trivia => Do_Print_Trivia);
      Parser.Mem_Pool := Pool;

      % for i, (rule_name, parser) in \
            enumerate(_self.rules_to_fn_names.items()):
         ${"if" if i == 0 else "elsif"}
            Rule_Name.all = ${string_repr(rule_name)}
         then
            declare
               Res : ${parser.get_type().name()} :=
                  Parse_${parser._name} (Parser);
            begin
               if not Parser.Diagnostics.Is_Empty then
                  Put_Line ("Parsing failed:");
                  for D of Parser.Diagnostics loop
                     Put_Line (To_Pretty_String (D));
                  end loop;
               end if;

               ## Error recovery may make the parser return something even on
               ## error: print anyway.
               % if is_ast_node(parser.get_type()):
                  Process_Node (${root_node_type_name} (Res));
               % else:
                  Put_Line (${parser.get_type().name()}'Image (Res));
                  if not Lookups.Is_Empty then
                     Put_Line ("Cannot lookup non-AST nodes!");
                  end if;
               % endif
            end;

      % endfor

         else
            raise Program_Error with "Unknown rule: " & Rule_Name.all;
         end if;

      Free (TDH);
      Destroy (Symbols);
      Free (Pool);
   end Parse_Input;

   procedure Process_File (File_Name : String; Ctx : in out Analysis_Context) is
      Unit         : Analysis_Unit;
      Time_Before  : constant Time := Clock;
      Time_After   : Time;
      AST          : ${root_node_type_name};
   begin
      Unit := Get_From_File (Ctx, File_Name, "", True,
                             With_Trivia => Do_Print_Trivia);
      AST := Root (Unit);
      Time_After := Clock;

      if Has_Diagnostics (Unit) then
         Put_Line ("Errors while parsing " & File_Name);
         for D of Diagnostics (Unit) loop
            Put_Line (To_Pretty_String (D));
         end loop;

      elsif not Silent then
         if Do_Print_Trivia then
            PP_Trivia (Unit);
         else
            AST.Print;
         end if;
      end if;

      if Print_Envs then
         Populate_Lexical_Env (Unit);
         Put_Line ("");
         Put_Line ("==== Dumping lexical environments ====");
         Dump_Lexical_Env (Unit);
      end if;

      if Measure_Time then
         Put_Line
           ("Time elapsed: " & Duration'Image (Time_After - Time_Before));
      end if;

   end Process_File;

begin
   Initialize;

   Set_Usage
     (Config,
      Usage    => "[switches] [input] [lookups]");
   Define_Switch
     (Config, Silent'Access, "-s", "--silent",
      Help   => "Do not print the representation of the resulting tree");
   Define_Switch
     (Config, Print_Envs'Access, "-E", "--print-envs",
      Help   => "Print lexical environments computed");
   Define_Switch
     (Config, Measure_Time'Access, "-t", "--time",
      Help   => "Time the execution of parsing");
   Define_Switch
     (Config, Rule_Name'Access, "-r:", "--rule-name:",
      Help   => "Rule name to parse");
   Define_Switch
     (Config, Charset'Access, "-c:", "--charset:",
      Help   => "Charset to use to decode the source code");
   Define_Switch
     (Config, Do_Print_Trivia'Access, "-P", "--print-with-trivia",
      Help   => "Print a simplified tree with trivia included");
   Define_Switch
     (Config, File_Name'Access, "-f:", "--file-name:",
      Help   => "Parse file");
   Define_Switch
     (Config, File_List'Access, "-F:", "--file-list:",
      Help   => ("Parse files listed in the provided filename with the regular"
                 & " analysis circuitry (useful for timing measurements)"));
   begin
      Getopt (Config);
   exception
      when GNAT.Command_Line.Exit_From_Command_Line =>
         return;
   end;

   if File_List.all'Length /= 0 then
      declare
         F : File_Type;
         Ctx : Analysis_Context := Create (Charset.all);
      begin
         Open (F, In_File, File_List.all);
         while not End_Of_File (F) loop
            declare
               Filename : String := Get_Line (F);
            begin
               Process_File (Filename, Ctx);
               Remove (Ctx, Filename);
            end;
         end loop;
         Close (F);
         Destroy (Ctx);
      end;

   elsif File_Name.all'Length /= 0 then
      declare
         Ctx : Analysis_Context := Create (Charset.all);
      begin
         Process_File (File_Name.all, Ctx);
         Destroy (Ctx);
      end;

   else
      Input_Str := +Get_Argument;
      loop
         declare
            Arg : String := Get_Argument;
         begin
            exit when Arg'Length = 0;
            Lookups.Append (+Arg);
         end;
      end loop;

      declare
         Time_Before : constant Time := Clock;
         Time_After  : Time;
      begin
         Parse_Input;
         Time_After := Clock;
         if Measure_Time then
            Put_Line
              ("Time elapsed: " & Duration'Image (Time_After - Time_Before));
         end if;
      end;

   end if;

   GNAT.Strings.Free (Rule_Name);
   GNAT.Strings.Free (Charset);
   GNAT.Strings.Free (File_List);
   GNAT.Strings.Free (File_Name);
   Free (Config);
end Parse;
