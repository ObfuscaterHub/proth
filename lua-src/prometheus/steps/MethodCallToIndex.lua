local Step = require("prometheus.step");
local Ast = require("prometheus.ast");
local Scope = require("prometheus.scope");
local visitast = require("prometheus.visitast");

local AstKind = Ast.AstKind;

local MethodCallToIndex = Step:extend();
MethodCallToIndex.Description = "This Step converts method-call syntax (a:b(...)) into index + call syntax (a[\"b\"](a, ...)), so method names stop leaking in plaintext and become subject to string encryption.";
MethodCallToIndex.Name = "Method Call To Index";

MethodCallToIndex.SettingsDescriptor = {}

function MethodCallToIndex:init(settings)

end

local function expandStatement(statement, scope)
	local id = scope:addVariable();
	local localDecl = Ast.LocalVariableDeclaration(scope, { id }, { statement.base });

	local args = { Ast.VariableExpression(scope, id) };
	for i, arg in ipairs(statement.args) do
		args[i + 1] = arg;
	end

	local newCall = Ast.FunctionCallStatement(
		Ast.IndexExpression(Ast.VariableExpression(scope, id), Ast.StringExpression(statement.passSelfFunctionName)),
		args
	);

	return localDecl, newCall;
end

local function isAncestorScope(candidate, scope)
	local s = scope.parentScope;
	while s do
		if s == candidate then return true end
		s = s.parentScope;
	end
	return false;
end

local function expandExpression(expression, parentScope)
	local scope = Scope:new(parentScope);
	local id = scope:addVariable();
	local param = Ast.VariableExpression(scope, id);

	local args = { Ast.VariableExpression(scope, id) };
	for i, arg in ipairs(expression.args) do
		args[i + 1] = arg;
	end

	local call = Ast.FunctionCallExpression(
		Ast.IndexExpression(Ast.VariableExpression(scope, id), Ast.StringExpression(expression.passSelfFunctionName)),
		args
	);

	local body = Ast.Block({ Ast.ReturnStatement({ call }) }, scope);

	local globalScope = parentScope;
	while not globalScope.isGlobal do
		globalScope = globalScope.parentScope;
	end
	visitast({ body = body, globalScope = globalScope }, function(node, data)
		if node.kind == AstKind.VariableExpression or node.kind == AstKind.AssignmentVariable then
			if node.scope ~= scope and isAncestorScope(node.scope, scope) then
				scope:addReferenceToHigherScope(node.scope, node.id);
			end
		end
	end, nil);

	local literal = Ast.FunctionLiteralExpression({ param }, body);

	return Ast.FunctionCallExpression(literal, { expression.base });
end

function MethodCallToIndex:apply(ast)
	visitast(ast, nil, function(node, data)
		if node.kind == AstKind.PassSelfFunctionCallStatement then
			return expandStatement(node, data.scope);
		elseif node.kind == AstKind.PassSelfFunctionCallExpression then
			return expandExpression(node, data.scope);
		end
	end);
end

return MethodCallToIndex;
