with Ada.Text_IO; use Ada.Text_IO;

with System.Assertions;

with Libfoolang.Analysis;      use Libfoolang.Analysis;
with Libfoolang.Introspection; use Libfoolang.Introspection;
with Libfoolang.Rewriting;     use Libfoolang.Rewriting;

with Process_Apply;

procedure Rewrite is
   Buffer : constant String :=
     ("def a = 1" & ASCII.LF
      & "def b = (2 + a) + 3" & ASCII.LF
      & "def c = a + b" & ASCII.LF
      & "def d = 4" & ASCII.LF
      & "def e = 5" & ASCII.LF);

   procedure Try (Label : String; Proc : access procedure);

   ---------
   -- Try --
   ---------

   procedure Try (Label : String; Proc : access procedure) is
   begin
      Put_Line (Label & "...");
      Proc.all;
      Put_Line ("   Done with no assert failure");
   exception
      when System.Assertions.Assert_Failure =>
         Put_Line ("   Got an assert failure");
   end Try;

   Ctx : constant Analysis_Context := Create;
   U   : constant Analysis_Unit := Get_From_Buffer
     (Ctx, "main.txt", Buffer => Buffer);
   RH  : Rewriting_Handle;
   N   : Node_Rewriting_Handle;
begin
   if Has_Diagnostics (U) then
      Put_Line ("Errors:");
      for D of Diagnostics (U) loop
         Put_Line (Format_GNU_Diagnostic (U, D));
      end loop;
      return;
   end if;

   RH := Start_Rewriting (Ctx);
   N := Handle (Root (U));

   declare
      procedure Proc;

      ----------
      -- Proc --
      ----------

      procedure Proc is
      begin
         Set_Child (N, 2, Child (N, 3));
      end Proc;
   begin
      Try ("Try assigning a child that is already tied to a tree",
           Proc'Access);

      New_Line;
      Put_Line ("Replace the middle definition (b) with a clone of the last"
                & " definition (c)");
      Set_Child (N, 2, Clone (Child (N, 3)));
   end;

   New_Line;
   Put_Line ("Swap first and fourth defs");
   declare
      N1 : constant Node_Rewriting_Handle := Child (N, 1);
      N4 : constant Node_Rewriting_Handle := Child (N, 4);
   begin
      if not Tied (N1) then
         raise Program_Error;
      end if;
      if not Tied (N4) then
         raise Program_Error;
      end if;

      Set_Child (N, 1, No_Node_Rewriting_Handle);
      Set_Child (N, 4, No_Node_Rewriting_Handle);

      if Tied (N1) then
         raise Program_Error;
      end if;
      if Tied (N4) then
         raise Program_Error;
      end if;

      Set_Child (N, 1, N4);
      Set_Child (N, 4, N1);

      if not Tied (N1) then
         raise Program_Error;
      end if;
      if not Tied (N4) then
         raise Program_Error;
      end if;
   end;

   New_Line;
   Put_Line ("Replace the expression of the fifth definition");
   declare
      Nested_Expr : constant Node_Rewriting_Handle := Create_Parent_Expr
        (RH, Create_Plus
               (RH,
                Create_Token_Node (RH, Foo_Literal, "5"),
                Create_Ref (RH, Create_Token_Node (RH, Foo_Name, "c"))));

      Top_Expr : constant Node_Rewriting_Handle := Create_Parent_Expr
        (RH, Create_Plus
               (RH,
                Create_Ref (RH, Create_Token_Node (RH, Foo_Name, "d")),
                Nested_Expr));
   begin
      Set_Child
        (Child (N, 5),
         Index (Def_F_Expr),
         Top_Expr);
   end;

   New_Line;
   Put_Line ("Applying the diff...");
   Process_Apply (RH);

   Root (U).Print (Show_Slocs => False);

   Put_Line ("rewrite.adb: Done.");
end Rewrite;
