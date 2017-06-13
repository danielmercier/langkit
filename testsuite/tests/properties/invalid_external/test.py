from __future__ import absolute_import, division, print_function

from langkit.diagnostics import Diagnostics
from langkit.dsl import ASTNode, T, abstract, root_grammar_class
from langkit.expressions import ExternalProperty, Property, Self
from langkit.parsers import Grammar, Row

from os import path
from utils import emit_and_print_errors


def run(name, abstract_prop, prop=None):
    """
    Emit and print the errors we get for the below grammar with "expr" as
    a property in BarNode.
    """

    Diagnostics.set_lang_source_dir(path.abspath(__file__))

    print('== {} =='.format(name))

    @root_grammar_class
    class FooNode(ASTNode):
        pass

    @abstract
    class AbstractExample(FooNode):
        p = abstract_prop()

    class Example(AbstractExample):
        if prop:
            p = prop()

    def lang_def():
        foo_grammar = Grammar('main_rule')
        foo_grammar.add_rules(
            main_rule=Row('example') ^ Example,
        )
        return foo_grammar
    emit_and_print_errors(lang_def)
    print('')


run("Missing type",
    lambda: ExternalProperty(uses_entity_info=False))

run("Invalid abstract",
    lambda: ExternalProperty(abstract=True, type=T.FooNode,
                             uses_entity_info=False),
    lambda: Property(Self))

run("Invalid memoized",
    lambda: ExternalProperty(memoized=True, uses_entity_info=False))
print('Done')
