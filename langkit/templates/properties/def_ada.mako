## vim: filetype=makoada

<%namespace name="scopes"  file="scopes_ada.mako" />
<%namespace name="helpers" file="helpers.mako" />

## Regular property function


% if property.abstract_runtime_check:

${"overriding" if property.overriding else ""} function ${property.name}
  ${helpers.argument_list(property, property.dispatching)}
   return ${property.type.name}
is (raise Property_Error
    with "Property ${property.name} not implemented on type "
    & Kind_Name (${Self.type.name} (${property.self_arg_name})));

% elif not property.abstract and not property.external:
${gdb_helper('property-start',
             property.qualname,
             '{}:{}'.format(property.location.file, property.location.line))}
pragma Warnings (Off, "is not referenced");
${"overriding" if property.overriding else ""} function ${property.name}
  ${helpers.argument_list(property, property.dispatching)}
   return ${property.type.name}
is
   use type AST_Envs.Lexical_Env;

   ## We declare a variable Self, that has the named class wide access type
   ## that we can use to dispatch on other properties and all.
   Self : ${Self.type.name} := ${Self.type.name}
     (${property.self_arg_name});
   ${gdb_helper('bind', 'self', 'Self')}

   % if property._has_self_entity:
   Ent : ${Self.type.entity.name} :=
     ${Self.type.entity.name}'(Info => E_Info, El => Self);
   % endif

   % for arg in property.arguments:
   ${gdb_helper('bind', arg.name.lower, arg.name.camel_with_underscores)}
   % endfor

   Property_Result : ${property.type.name} := ${property.type.nullexpr};

   ## For each scope, there is one of the following subprograms that finalizes
   ## all the ref-counted local variables it contains, excluding variables from
   ## children scopes.
   <% all_scopes = property.vars.all_scopes %>
   % for scope in all_scopes:
      % if scope.has_refcounted_vars():
         procedure ${scope.finalizer_name};
      % endif
   % endfor

   ${property.vars.render()}

   % for scope in all_scopes:
      % if scope.has_refcounted_vars():
         procedure ${scope.finalizer_name} is
         begin
            ## Finalize the local variable for this scope
            % for var in scope.variables:
               % if var.type.is_refcounted:
                  Dec_Ref (${var.name});
               % endif
            % endfor
         end ${scope.finalizer_name};
      % endif
   % endfor

begin
   % if property.memoized:
      case Self.${property.memoization_state_field_name} is
         when Not_Computed =>
            null;
         when Computed =>
            declare
               Result : constant ${property.type.name} :=
                  Self.${property.memoization_value_field_name};
            begin
               % if property.type.is_refcounted:
                  Inc_Ref (Result);
               % endif
               return Result;
            end;
         when Raise_Property_Error =>
            raise Property_Error;
      end case;
   % endif

   ${scopes.start_scope(property.vars.root_scope)}
   ${property.constructed_expr.render_pre()}

   Property_Result := ${property.constructed_expr.render_expr()};
   % if property.type.is_refcounted:
      Inc_Ref (Property_Result);
   % endif
   ${scopes.finalize_scope(property.vars.root_scope)}

   % if property.memoized:
      Self.${property.memoization_state_field_name} := Computed;
      Self.${property.memoization_value_field_name} := Property_Result;
      Set_Filled_Caches (Self.Unit);

      % if property.type.is_refcounted:
         Inc_Ref (Property_Result);
      % endif
   % endif

   return Property_Result;

% if property.vars.root_scope.has_refcounted_vars(True):
   exception
      when Property_Error =>
         % for scope in all_scopes:
            % if scope.has_refcounted_vars():
               ${scope.finalizer_name};
            % endif
         % endfor

         % if property.memoized:
            Self.${property.memoization_state_field_name} :=
               Raise_Property_Error;
         % endif

         raise;
% endif
end ${property.name};
${gdb_helper('end', property.qualname)}
% endif
